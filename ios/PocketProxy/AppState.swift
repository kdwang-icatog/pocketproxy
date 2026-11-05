import SwiftUI
import UIKit

@MainActor
final class AppState: ObservableObject {
    @Published var running = false
    @Published var port: String
    @Published var addresses: [NetInfo.Address] = []
    @Published var stats = ProxyServer.Stats()
    @Published var log: [String] = []
    @Published var error = ""
    @Published var locationStatus = ""
    @Published var startedAt: Date?
    @Published var audioKeepAlive: Bool {
        didSet { UserDefaults.standard.set(audioKeepAlive, forKey: "audio"); applyKeepAlive() }
    }
    @Published var locationKeepAlive: Bool {
        didSet { UserDefaults.standard.set(locationKeepAlive, forKey: "location"); applyKeepAlive() }
    }
    @Published var screenOn: Bool {
        didSet { UserDefaults.standard.set(screenOn, forKey: "screenOn"); UIApplication.shared.isIdleTimerDisabled = screenOn }
    }

    let server = ProxyServer()
    let keep = KeepAlive()
    private var wantRunning = true
    private var timer: Timer?

    static var version: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?" }

    init() {
        let d = UserDefaults.standard
        d.register(defaults: ["port": 8080, "audio": true, "location": false, "screenOn": false])
        port = String(d.integer(forKey: "port"))
        audioKeepAlive = d.bool(forKey: "audio")
        locationKeepAlive = d.bool(forKey: "location")
        screenOn = d.bool(forKey: "screenOn")
        server.onEvent = { [weak self] m in Task { @MainActor in self?.add(m) } }
        keep.onEvent = { [weak self] m in Task { @MainActor in self?.add(m) } }
        add("口袋代理 \(Self.version) 启动")
        UIApplication.shared.isIdleTimerDisabled = screenOn
        applyKeepAlive()
        start()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    var statusText: String {
        guard running else { return "已停止" }
        let mins = Int(Date().timeIntervalSince(startedAt ?? Date()) / 60)
        return "运行中 · 已运行 \(mins) 分钟"
    }

    func start() {
        error = ""
        guard let p = UInt16(port), p >= 1024 else { error = "端口要在 1024–65535 之间"; return }
        do {
            try server.start(port: p)
            UserDefaults.standard.set(Int(p), forKey: "port")
            wantRunning = true
            startedAt = Date()
        } catch {
            self.error = "端口 \(p) 用不了:\(error.localizedDescription),换一个试试"
        }
        refresh()
    }

    func stop() {
        wantRunning = false
        server.stop()
        startedAt = nil
        refresh()
    }

    /// 回到前台:代理端口要是在后台失效了,自动重开
    func becameActive() {
        if wantRunning && !server.isRunning {
            add("回到前台,代理端口已失效,重新打开")
            start()
        }
        if audioKeepAlive && !keep.audioOn { keep.startAudio() }
        refresh()
    }

    func applyKeepAlive() {
        if audioKeepAlive { keep.startAudio() } else { keep.stopAudio() }
        if locationKeepAlive { keep.startLocation() } else { keep.stopLocation() }
    }

    func refresh() {
        running = server.isRunning
        stats = server.snapshot()
        addresses = NetInfo.addresses()
        locationStatus = keep.locationText
    }

    func add(_ m: String) {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm:ss"
        log.append("\(f.string(from: Date())) \(m)")
        if log.count > 300 { log.removeFirst(log.count - 300) }
    }
}
