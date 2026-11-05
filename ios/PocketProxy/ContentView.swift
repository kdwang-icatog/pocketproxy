import SwiftUI

struct ContentView: View {
    @EnvironmentObject var s: AppState

    private func size(_ n: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: n, countStyle: .binary)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 8) {
                        Circle().fill(s.running ? Color.green : Color.red).frame(width: 12, height: 12)
                        Text(s.statusText).font(.headline)
                    }
                }

                Section("电脑上填的代理地址") {
                    if let a = s.addresses.first {
                        Text(a.ip)
                            .font(.system(size: 30, weight: .semibold, design: .monospaced))
                            .textSelection(.enabled)
                        Text(a.kind).foregroundStyle(.secondary)
                        ForEach(Array(s.addresses.dropFirst())) { x in
                            Text("也可以用:\(x.ip)(\(x.kind))").font(.footnote)
                        }
                    } else {
                        Text("没找到网络:请打开个人热点,或连上 Wi-Fi").foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("端口")
                        TextField("8080", text: $s.port)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .disabled(s.running)
                    }
                    if !s.error.isEmpty {
                        Text(s.error).foregroundStyle(.red).font(.footnote)
                    }
                }

                Section {
                    Button {
                        if s.running { s.stop() } else { s.start() }
                    } label: {
                        Text(s.running ? "停止" : "启动")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .tint(s.running ? Color.red : Color.accentColor)
                }

                Section {
                    Toggle("静音音频保活", isOn: $s.audioKeepAlive)
                    Toggle("定位保活", isOn: $s.locationKeepAlive)
                    if s.locationKeepAlive {
                        Text("定位:\(s.locationStatus)").font(.footnote).foregroundStyle(.secondary)
                    }
                    Toggle("屏幕常亮", isOn: $s.screenOn)
                } header: {
                    Text("后台保持运行")
                } footer: {
                    Text("""
                    静音音频:播放无声音频,让 iOS 不暂停口袋代理。不需要任何权限,不影响你听歌;来电、闹钟时会短暂中断,结束后自动恢复。
                    定位:更稳,但需要定位权限。位置只用来让口袋代理在后台继续运行,不保存、不上传;开着时屏幕顶部会显示定位图标。
                    屏幕常亮:手机停在这个页面时最稳。
                    """)
                }

                Section("统计") {
                    LabeledContent("当前连接", value: "\(s.stats.active)")
                    LabeledContent("累计连接", value: "\(s.stats.total)")
                    LabeledContent("上传", value: size(s.stats.sent))
                    LabeledContent("下载", value: size(s.stats.recv))
                }

                Section("电脑怎么设置") {
                    Text("""
                    1. 电脑连 iPhone 的个人热点,或和 iPhone 连同一个 Wi-Fi。
                    2. 电脑的代理设成上面的地址和端口(HTTP、HTTPS、SOCKS5 都可以用这个端口)。
                       Windows:设置 → 网络和 Internet → 代理 → 手动设置代理。
                       Mac:系统设置 → 网络 → 详细信息 → 代理,勾选网页代理和安全网页代理。
                    3. 电脑浏览器打开 http://地址:端口/ ,看到"口袋代理正在运行"就是通的。
                    """).font(.footnote)
                }

                Section("最近记录") {
                    ForEach(Array(s.log.suffix(40).reversed().enumerated()), id: \.offset) { item in
                        Text(item.element).font(.caption.monospaced())
                    }
                }
            }
            .navigationTitle("口袋代理")
        }
    }
}
