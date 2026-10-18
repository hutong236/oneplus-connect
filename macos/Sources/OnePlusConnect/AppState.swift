import Foundation
import SwiftUI

/// 状态机与主链路编排：BLE 连接 → 指令开热点 → 加入 Wi-Fi → 连通性验证
@MainActor
final class AppState: ObservableObject {

    enum Phase: Equatable {
        case idle
        case requestingWiFiAccess
        case bleSearching
        case hotspotStarting
        case joiningWifi
        case verifying
        case leavingWifi
        case disconnected(warning: String)
        case connected(gateway: String, internetReachable: Bool)
        case failed(String)

        var isRunning: Bool {
            switch self {
            case .requestingWiFiAccess, .bleSearching, .hotspotStarting, .joiningWifi, .verifying, .leavingWifi: return true
            default: return false
            }
        }

        var label: String {
            switch self {
            case .idle: return "未连接"
            case .requestingWiFiAccess: return "正在检查 Wi-Fi 读取权限，请允许位置访问 …"
            case .bleSearching: return "正在搜索 OnePlus 6T …"
            case .hotspotStarting: return "BLE 已连接，正在开启手机热点 …"
            case .joiningWifi: return "热点已开启，正在加入 Wi-Fi …"
            case .verifying: return "验证网络连通性 …"
            case .leavingWifi: return "正在退出手机热点 Wi-Fi …"
            case .disconnected(let warning): return "已断开；\(warning)"
            case .connected(let gateway, let internet):
                return internet ? "热点已连接（网关 \(gateway)，互联网探测通过）" : "热点已连接（网关 \(gateway)，互联网探测未通过）"
            case .failed(let reason): return "失败：\(reason)"
            }
        }
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var battery: Int?
    @Published private(set) var hotspotOn = false
    @Published var log: [String] = []

    private let ble: any BleConnection
    private let defaults: UserDefaults
    private var logTimeFormatter = DateFormatter()
    private let wifi: WiFiSession
    private var reconnectTask: Task<Void, Never>?
    private var reconnectAttempts = 0
    private var wantsConnection = true

    init(ble: (any BleConnection)? = nil, defaults: UserDefaults = .standard,
         wifi: WiFiSession? = nil) {
        self.ble = ble ?? BleCentral()
        self.defaults = defaults
        self.wifi = wifi ?? WiFiSession()
        logTimeFormatter.dateFormat = "HH:mm:ss"
        self.ble.onStatus = { [weak self] status in
            Task { @MainActor in
                guard let self else { return }
                self.battery = status.batteryPercent
                self.hotspotOn = status.hotspotOn
                if status.cmdFailed {
                    self.note("手机端报告：指令执行失败（详见手机日志）")
                }
            }
        }
        self.ble.onUnexpectedDisconnect = { [weak self] in
            self?.scheduleReconnect()
        }
        defaults.register(defaults: ["autoConnect": true, "autoReconnect": true])
        Task { [weak self] in
            guard defaults.bool(forKey: "autoConnect") else { return }
            self?.connect()
        }
    }

    func connect() {
        guard !phase.isRunning else { return }
        wantsConnection = true
        phase = .requestingWiFiAccess
        reconnectTask?.cancel()
        reconnectTask = nil
        Task { await runConnectChain() }
    }

    func setAutoReconnect(_ enabled: Bool) {
        defaults.set(enabled, forKey: "autoReconnect")
        if !enabled {
            reconnectTask?.cancel()
            reconnectTask = nil
            reconnectAttempts = 0
        }
    }

    func disconnect(closeHotspot: Bool = true) {
        guard !phase.isRunning else { return }
        wantsConnection = false
        phase = .bleSearching
        reconnectTask?.cancel()
        reconnectTask = nil
        reconnectAttempts = 0
        Task { await runDisconnectChain(closeHotspot: closeHotspot) }
    }

    private func runConnectChain() async {
        do {
            guard AppConfig.sharedSecret.utf8.count >= 32 else {
                phase = .failed("未配置 BLE 配对密钥，请按配对说明设置 Keychain")
                note("缺少 BLE 配对密钥，未启动自动连接")
                return
            }
            phase = .requestingWiFiAccess
            try await WiFiLocationAccess.shared.ensureAuthorized()
            phase = .bleSearching
            note("搜索 OnePlus Agent 广播 …")
            try await ble.ensurePoweredOn(timeout: 5)
            try await ble.connect(timeout: AppConfig.scanTimeout)
            note("BLE 已连接，发送 CONNECT 指令")

            phase = .hotspotStarting
            let status = try await ble.send(BleProtocol.cmdConnect,
                                            expectingHotspotOn: true,
                                            timeout: AppConfig.hotspotTimeout)
            battery = status.batteryPercent
            hotspotOn = status.hotspotOn

            phase = .joiningWifi
            let ssid = status.ssid ?? AppConfig.hotspotSSID
            note("热点已开启（SSID: \(ssid)），加入 Wi-Fi …")
            try await HotspotJoiner.join(ssid: ssid, password: AppConfig.wifiPassword)

            phase = .verifying
            let verification = try await ConnectivityCheck.waitUntilOnline(ssid: ssid,
                                                                            timeout: AppConfig.joinTimeout)
            phase = .connected(gateway: verification.gateway,
                               internetReachable: verification.internetReachable)
            reconnectAttempts = 0
            note("热点链路已验证：\(verification.wifiInterface)，网关 \(verification.gateway)，互联网探测\(verification.internetReachable ? "通过" : "未通过（不代表无法上网）")，按当前系统路由检测")
        } catch {
            phase = .failed(error.localizedDescription)
            note("失败：\(error.localizedDescription)")
            if !(error is WiFiAccessError) { scheduleReconnect() }
        }
    }

    private func runDisconnectChain(closeHotspot: Bool) async {
        do {
            if closeHotspot {
                try await ble.ensurePoweredOn(timeout: 5)
                try await ble.connect(timeout: AppConfig.scanTimeout)
                let status = try await ble.send(BleProtocol.cmdDisconnect,
                                                expectingHotspotOn: false,
                                                timeout: AppConfig.hotspotTimeout)
                hotspotOn = status.hotspotOn
                battery = status.batteryPercent
            }
            ble.disconnect()
            let result = closeHotspot ? "手机热点已关闭" : "已断开 Mac 连接，保留手机热点"
            phase = .leavingWifi
            do {
                try await wifi.disconnect()
                note("\(result)；后续 Wi-Fi 连接交由 macOS 管理")
                phase = .idle
            } catch {
                phase = .disconnected(warning: "\(result)；退出手机热点 Wi-Fi 失败：\(error.localizedDescription)")
                note("\(result)；退出手机热点 Wi-Fi 失败：\(error.localizedDescription)")
            }
        } catch {
            phase = .failed(error.localizedDescription)
            note("断开失败：\(error.localizedDescription)")
        }
    }

    private func note(_ message: String) {
        log.append("\(logTimeFormatter.string(from: Date()))  \(message)")
        if log.count > 200 { log.removeFirst(log.count - 200) }
        print(message)
    }

    private func scheduleReconnect() {
        guard defaults.bool(forKey: "autoReconnect"),
              wantsConnection,
              reconnectTask == nil,
              !phase.isRunning,
              reconnectAttempts < 5 else { return }
        let delays: [UInt64] = [3, 8, 15, 30, 60]
        let delay = delays[reconnectAttempts]
        reconnectAttempts += 1
        note("连接中断，\(delay) 秒后自动重连（\(reconnectAttempts)/5）")
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delay * 1_000_000_000)
            guard !Task.isCancelled, let self,
                  self.wantsConnection,
                  self.defaults.bool(forKey: "autoReconnect") else { return }
            self.reconnectTask = nil
            self.connect()
        }
    }
}
