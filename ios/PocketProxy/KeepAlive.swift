import AVFoundation
import CoreLocation

/// 让 iOS 不把口袋代理挂起(挂起后电脑就连不进来了)。
/// - 静音音频:播放无声音频,不需要任何权限,和别的 App 的声音混在一起,不打断你听歌。默认开。
/// - 定位:更稳,但需要定位权限;位置只用来保持运行,不保存、不上传。默认关,用户自己打开。
final class KeepAlive: NSObject, CLLocationManagerDelegate {
    var onEvent: ((String) -> Void)?
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var silence: AVAudioPCMBuffer?
    private var wantAudio = false
    private let location = CLLocationManager()
    private var wantLocation = false
    private(set) var lastLocationAt: Date?

    override init() {
        super.init()
        location.delegate = self
        engine.attach(player)
        if let fmt = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2) {
            engine.connect(player, to: engine.mainMixerNode, format: fmt)
            if let b = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: 44100) {
                b.frameLength = 44100  // 新建的缓冲区全是 0,就是一秒静音
                silence = b
            }
        }
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(audioInterrupted(_:)), name: AVAudioSession.interruptionNotification, object: nil)
        nc.addObserver(self, selector: #selector(mediaReset), name: AVAudioSession.mediaServicesWereResetNotification, object: nil)
    }

    var audioOn: Bool { wantAudio && engine.isRunning }

    // MARK: 静音音频

    func startAudio() {
        wantAudio = true
        do {
            let s = AVAudioSession.sharedInstance()
            try s.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try s.setActive(true)
            if !engine.isRunning { try engine.start() }
            player.stop()
            if let b = silence { player.scheduleBuffer(b, at: nil, options: .loops) }
            player.play()
            onEvent?("静音音频保活已开启")
        } catch {
            onEvent?("静音音频保活开启失败:\(error.localizedDescription)")
        }
    }

    func stopAudio() {
        guard wantAudio else { return }
        wantAudio = false
        player.stop()
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        onEvent?("静音音频保活已关闭")
    }

    @objc private func audioInterrupted(_ n: Notification) {
        guard let raw = n.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        if type == .began {
            onEvent?("静音音频被打断(来电、闹钟等),结束后自动恢复")
        } else if wantAudio {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.startAudio() }
        }
    }

    @objc private func mediaReset() {
        guard wantAudio else { return }
        DispatchQueue.main.async { [weak self] in self?.startAudio() }
    }

    // MARK: 定位(可选)

    func startLocation() {
        wantLocation = true
        location.desiredAccuracy = kCLLocationAccuracyThreeKilometers  // 只要能保持运行,精度越低越省电
        location.pausesLocationUpdatesAutomatically = false
        location.showsBackgroundLocationIndicator = true
        if location.authorizationStatus == .notDetermined {
            location.requestAlwaysAuthorization()
        }
        location.allowsBackgroundLocationUpdates = true
        location.startUpdatingLocation()
        onEvent?("定位保活已开启")
    }

    func stopLocation() {
        guard wantLocation else { return }
        wantLocation = false
        location.stopUpdatingLocation()
        location.allowsBackgroundLocationUpdates = false
        onEvent?("定位保活已关闭")
    }

    var locationText: String {
        guard wantLocation else { return "未开启" }
        switch location.authorizationStatus {
        case .denied, .restricted: return "没有定位权限,定位保活不起作用(可到 设置 → 口袋代理 → 位置 打开)"
        case .notDetermined: return "等待授权"
        default: break
        }
        if let t = lastLocationAt, Date().timeIntervalSince(t) < 120 { return "正常" }
        return "还没收到定位"
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        lastLocationAt = Date()  // 只记时间,位置本身不保存
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard wantLocation else { return }
        switch manager.authorizationStatus {
        case .denied, .restricted: onEvent?("没有定位权限,定位保活不起作用")
        case .authorizedWhenInUse, .authorizedAlways: manager.startUpdatingLocation()
        default: break
        }
    }
}
