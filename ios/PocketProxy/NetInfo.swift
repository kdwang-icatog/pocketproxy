import Foundation
import Network

/// 本机地址(电脑要填哪个)和"连进来的是不是局域网设备"的判断。
enum NetInfo {
    struct Address: Identifiable, Equatable {
        let ip: String
        let kind: String
        var id: String { ip }
    }

    /// 个人热点(bridge 开头的网卡,地址一般是 172.20.10.1)排第一,其次是 Wi-Fi(en0)。VPN 的虚拟网卡不算。
    static func addresses() -> [Address] {
        var hotspot: [Address] = [], wifi: [Address] = []
        var ifap: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifap) == 0, let first = ifap else { return [] }
        defer { freeifaddrs(ifap) }
        for p in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let ifa = p.pointee
            guard let sa = ifa.ifa_addr, sa.pointee.sa_family == UInt8(AF_INET) else { continue }
            let name = String(cString: ifa.ifa_name)
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(sa, socklen_t(sa.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else { continue }
            let ip = String(cString: host)
            if name.hasPrefix("bridge") {
                hotspot.append(Address(ip: ip, kind: "个人热点"))
            } else if name == "en0" {
                wifi.append(Address(ip: ip, kind: "无线局域网"))
            }
        }
        return hotspot + wifi
    }

    /// 只接受局域网和本机的连接
    static func isLocal(_ ep: NWEndpoint) -> Bool {
        guard case .hostPort(let host, _) = ep else { return false }
        switch host {
        case .ipv4(let a):
            return isLocal4([UInt8](a.rawValue))
        case .ipv6(let a):
            if let v4 = a.asIPv4 { return isLocal4([UInt8](v4.rawValue)) }
            let b = [UInt8](a.rawValue)
            return a == .loopback || (b[0] == 0xfe && (b[1] & 0xc0) == 0x80) || (b[0] & 0xfe) == 0xfc
        default:
            return false
        }
    }

    private static func isLocal4(_ b: [UInt8]) -> Bool {
        guard b.count == 4 else { return false }
        return b[0] == 127 || b[0] == 10 || (b[0] == 192 && b[1] == 168)
            || (b[0] == 172 && (16...31).contains(b[1])) || (b[0] == 169 && b[1] == 254)
    }
}
