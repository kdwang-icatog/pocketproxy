import Foundation
import Network

enum ProxyError: LocalizedError {
    case badPort
    var errorDescription: String? { "端口要在 1024–65535 之间" }
}

/// 代理服务:同一端口支持 HTTP、HTTPS(CONNECT)和 SOCKS5。出站连接走 iPhone 当前的网络(VPN 连着时就是 VPN)。
/// 所有连接的状态只在 queue 上改。
final class ProxyServer {
    struct Stats {
        var active = 0, total = 0, failed = 0
        var sent: Int64 = 0, recv: Int64 = 0
    }

    let queue = DispatchQueue(label: "pocketproxy.proxy")
    var onEvent: ((String) -> Void)?
    static let maxClients = 64
    static let idleSeconds: TimeInterval = 120

    private var listener: NWListener?
    private var sessions: [ObjectIdentifier: Session] = [:]
    private var stats = Stats()
    private var idleTimer: DispatchSourceTimer?
    private(set) var port: UInt16 = 8080
    private var listenerFailed = false

    /// 只在主线程调用 start / stop / isRunning
    var isRunning: Bool { listener != nil && !queue.sync { listenerFailed } }

    func start(port: UInt16) throws {
        stop(quiet: true)
        guard port >= 1024, let p = NWEndpoint.Port(rawValue: port) else { throw ProxyError.badPort }
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        let l = try NWListener(using: params, on: p)
        queue.sync { listenerFailed = false; stats = Stats() }
        l.newConnectionHandler = { [weak self] c in self?.accept(c) }
        l.stateUpdateHandler = { [weak self] st in
            guard let self else { return }
            switch st {
            case .ready: self.onEvent?("代理已启动,端口 \(port)")
            case .failed(let e):
                self.listenerFailed = true
                self.onEvent?("代理端口出错:\(e.localizedDescription)")
            default: break
            }
        }
        listener = l
        self.port = port
        l.start(queue: queue)
        startIdleTimer()
    }

    func stop(quiet: Bool = false) {
        guard let l = listener else { return }
        l.cancel()
        listener = nil
        idleTimer?.cancel()
        idleTimer = nil
        queue.async {
            for s in Array(self.sessions.values) { s.close() }
            self.sessions.removeAll()
        }
        if !quiet { onEvent?("代理已停止") }
    }

    func snapshot() -> Stats {
        queue.sync {
            var s = stats
            s.active = sessions.count
            return s
        }
    }

    // MARK: - 以下都在 queue 上

    private func accept(_ c: NWConnection) {
        guard NetInfo.isLocal(c.endpoint) else { c.cancel(); return }
        guard sessions.count < Self.maxClients else { c.cancel(); stats.failed += 1; return }
        let s = Session(client: c, server: self)
        sessions[ObjectIdentifier(s)] = s
        stats.total += 1
        s.start()
    }

    fileprivate func finished(_ s: Session) { sessions[ObjectIdentifier(s)] = nil }
    fileprivate func count(up: Int, down: Int) { stats.sent += Int64(up); stats.recv += Int64(down) }
    fileprivate func failed(_ msg: String) { stats.failed += 1; onEvent?(msg) }

    private func startIdleTimer() {
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + 30, repeating: 30)
        t.setEventHandler { [weak self] in
            guard let self else { return }
            let now = Date()
            for s in Array(self.sessions.values) where now.timeIntervalSince(s.last) > Self.idleSeconds { s.close() }
        }
        t.resume()
        idleTimer = t
    }
}

/// 一个电脑端连接
private final class Session {
    let client: NWConnection
    weak var server: ProxyServer?
    let queue: DispatchQueue
    var remote: NWConnection?
    var buf = Data()
    var last = Date()
    var closed = false
    var socksGreeted = false
    var halfClosed = 0
    var target = ""

    init(client: NWConnection, server: ProxyServer) {
        self.client = client
        self.server = server
        self.queue = server.queue
    }

    func start() {
        client.stateUpdateHandler = { [weak self] st in
            if case .failed = st { self?.close() }
        }
        client.start(queue: queue)
        readHead()
    }

    func close() {
        if closed { return }
        closed = true
        client.stateUpdateHandler = nil
        remote?.stateUpdateHandler = nil
        client.cancel()
        remote?.cancel()
        server?.finished(self)
    }

    // 先读到能判断协议的开头:0x05 是 SOCKS5,其余按 HTTP 读到空行
    private func readHead() {
        client.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, done, err in
            guard let self, !self.closed else { return }
            if let d = data { self.buf.append(d); self.last = Date() }
            if self.buf.count > 65536 { return self.close() }
            if self.buf.first == 0x05 {
                self.socks()
            } else if let r = self.buf.range(of: Data("\r\n\r\n".utf8)) {
                self.http(headerEnd: r.upperBound)
            } else if done || err != nil {
                self.close()
            } else {
                self.readHead()
            }
        }
    }

    // MARK: SOCKS5(只支持 CONNECT,不要密码)

    private func socks() {
        if !socksGreeted {
            guard buf.count >= 2 else { return readHead() }
            let n = 2 + Int(buf[buf.startIndex + 1])
            guard buf.count >= n else { return readHead() }
            buf = Data(buf.dropFirst(n))
            socksGreeted = true
            client.send(content: Data([5, 0]), completion: .contentProcessed { _ in })
            if buf.isEmpty { return readHead() }
        }
        let b = [UInt8](buf)
        guard b.count >= 4 else { return readHead() }
        guard b[1] == 1 else { return socksReply(7) }
        var host = ""
        var i = 0
        switch b[3] {
        case 1:
            guard b.count >= 10 else { return readHead() }
            host = b[4..<8].map { String($0) }.joined(separator: ".")
            i = 8
        case 3:
            guard b.count >= 5 else { return readHead() }
            let n = Int(b[4])
            guard b.count >= 5 + n + 2 else { return readHead() }
            host = String(decoding: b[5..<(5 + n)], as: UTF8.self)
            i = 5 + n
        case 4:
            guard b.count >= 22 else { return readHead() }
            host = IPv6Address(Data(b[4..<20])).map { "\($0)" } ?? ""
            i = 20
        default:
            return socksReply(8)
        }
        let port = UInt16(b[i]) << 8 | UInt16(b[i + 1])
        let rest = Data(b[(i + 2)...])
        buf = Data()
        connect(host: host, port: port) { [weak self] ok in
            guard let self else { return }
            if ok {
                self.socksReply(0) { self.forward(rest); self.pipe() }
            } else {
                self.socksReply(5)
            }
        }
    }

    private func socksReply(_ code: UInt8, then: (() -> Void)? = nil) {
        client.send(content: Data([5, code, 0, 1, 0, 0, 0, 0, 0, 0]), completion: .contentProcessed { [weak self] e in
            guard let self else { return }
            if code != 0 || e != nil { self.close() } else { then?() }
        })
    }

    // MARK: HTTP / HTTPS

    private func http(headerEnd: Data.Index) {
        let head = buf[buf.startIndex..<headerEnd]
        let rest = Data(buf[headerEnd...])
        buf = Data()
        let text = String(decoding: head, as: UTF8.self)
        var lines = text.components(separatedBy: "\r\n").filter { !$0.isEmpty }
        guard let first = lines.first else { return close() }
        let parts = first.split(separator: " ", maxSplits: 2).map(String.init)
        guard parts.count == 3 else { return close() }
        let method = parts[0], target = parts[1], version = parts[2]

        if method == "CONNECT" {
            let (h, p) = Self.hostPort(target, defaultPort: 443)
            connect(host: h, port: p) { [weak self] ok in
                guard let self else { return }
                guard ok else { return self.badGateway() }
                self.client.send(content: Data("HTTP/1.1 200 Connection Established\r\n\r\n".utf8), completion: .contentProcessed { [weak self] e in
                    guard let self else { return }
                    if e != nil { return self.close() }
                    self.forward(rest)
                    self.pipe()
                })
            }
            return
        }
        // 浏览器直接打开 http://地址:端口/ :显示运行状态,方便电脑上确认连通
        guard target.lowercased().hasPrefix("http://") else { return statusPage() }
        let afterScheme = target.dropFirst(7)
        let slash = afterScheme.firstIndex(of: "/") ?? afterScheme.endIndex
        let (h, p) = Self.hostPort(String(afterScheme[..<slash]), defaultPort: 80)
        let path = slash == afterScheme.endIndex ? "/" : String(afterScheme[slash...])
        lines[0] = "\(method) \(path) \(version)"
        lines = lines.filter {
            let k = $0.lowercased()
            return !k.hasPrefix("proxy-connection:") && !k.hasPrefix("connection:") && !k.hasPrefix("keep-alive:")
        }
        let newHead = (lines + ["Connection: close", "", ""]).joined(separator: "\r\n")
        connect(host: h, port: p) { [weak self] ok in
            guard let self else { return }
            guard ok else { return self.badGateway() }
            self.forward(Data(newHead.utf8) + rest)
            self.pipe()
        }
    }

    static func hostPort(_ s: String, defaultPort: UInt16) -> (String, UInt16) {
        if s.hasPrefix("["), let end = s.firstIndex(of: "]") {
            let h = String(s[s.index(after: s.startIndex)..<end])
            let r = s[s.index(after: end)...]
            return (h, r.hasPrefix(":") ? UInt16(r.dropFirst()) ?? defaultPort : defaultPort)
        }
        if s.filter({ $0 == ":" }).count == 1, let c = s.firstIndex(of: ":") {
            return (String(s[..<c]), UInt16(s[s.index(after: c)...]) ?? defaultPort)
        }
        return (s, defaultPort)
    }

    private func reply(_ text: String) {
        client.send(content: Data(text.utf8), completion: .contentProcessed { [weak self] _ in self?.close() })
    }

    private func statusPage() {
        let body = "<!doctype html><meta charset=utf-8><meta name=viewport content='width=device-width'>"
            + "<h2>口袋代理正在运行</h2><p>电脑经这个地址和端口上网。</p>"
        reply("HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nConnection: close\r\n\r\n" + body)
    }

    private func badGateway() {
        reply("HTTP/1.1 502 Bad Gateway\r\nContent-Type: text/plain; charset=utf-8\r\nConnection: close\r\n\r\n"
              + "口袋代理:iPhone 连不上 \(target),请检查 iPhone 的网络和 VPN。\n")
    }

    // MARK: 转发

    private func connect(host: String, port: UInt16, done: @escaping (Bool) -> Void) {
        target = "\(host):\(port)"
        guard !host.isEmpty, let p = NWEndpoint.Port(rawValue: port) else { return done(false) }
        let r = NWConnection(host: NWEndpoint.Host(host), port: p, using: .tcp)
        remote = r
        var called = false
        let finish: (Bool) -> Void = { [weak self] ok in
            if called { return }
            called = true
            if !ok, let self { self.server?.failed("\(self.target) 连接失败") }
            done(ok)
        }
        r.stateUpdateHandler = { [weak self] st in
            switch st {
            case .ready: finish(true)
            case .waiting: finish(false)
            case .failed, .cancelled:
                finish(false)
                self?.close()
            default: break
            }
        }
        r.start(queue: queue)
        queue.asyncAfter(deadline: .now() + 15) { finish(false) }
    }

    private func forward(_ d: Data) {
        guard !d.isEmpty, let r = remote else { return }
        server?.count(up: d.count, down: 0)
        r.send(content: d, completion: .contentProcessed { _ in })
    }

    private func pipe() {
        guard let r = remote else { return close() }
        pump(from: client, to: r, up: true)
        pump(from: r, to: client, up: false)
    }

    private func pump(from: NWConnection, to: NWConnection, up: Bool) {
        from.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, done, err in
            guard let self, !self.closed else { return }
            let finishDirection = {
                // 一边读完了:告诉另一边不会再发了;两边都读完才关
                to.send(content: nil, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { _ in })
                self.halfClosed += 1
                if self.halfClosed >= 2 { self.close() }
            }
            if let d = data, !d.isEmpty {
                self.last = Date()
                self.server?.count(up: up ? d.count : 0, down: up ? 0 : d.count)
                to.send(content: d, completion: .contentProcessed { [weak self] e in
                    guard let self, !self.closed else { return }
                    if e != nil { return self.close() }
                    if done { finishDirection() } else { self.pump(from: from, to: to, up: up) }
                })
            } else if err != nil {
                self.close()
            } else if done {
                finishDirection()
            } else {
                self.pump(from: from, to: to, up: up)
            }
        }
    }
}
