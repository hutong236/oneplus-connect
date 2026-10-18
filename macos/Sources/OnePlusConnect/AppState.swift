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
        case connected(gateway: String, internetReachable: Bool)
        case failed(String)

        var isRunning: Bool {
            switch self {
            case .requestingWiFiAccess, .bleSearching, .hotspotStarting, .joiningWifi, .verifying: return true
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
            case .connected(let gateway, let internet):
                return internet ? "热点已连接（网关 \(gateway)，互联网可达）" : "热点已连接（网关 \(gateway)，互联网不可直连）"
            case .failed(let reason): return "失败：\(reason)"
            }
        }
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var battery: Int?
    @Published private(set) var hotspotOn = false
    @Published var log: [String] = []

    private let ble = BleCentral()
    private var logTimeFormatter = DateFormatter()
    private var previousSSID: String?
    private var reconnectTask: Task<Void, Never>?
    private var reconnectAttempts = 0

    init() {
        logTimeFormatter.dateFormat = "HH:mm:ss"
        ble.onStatus = { [weak self] status in
            Task { @MainActor in
                guard let self else { return }
                self.battery = status.batteryPercent
                self.hotspotOn = status.hotspotOn
                if status.cmdFailed {
                    self.note("手机端报告：指令执行失败（详见手机日志）")
                }
            }
        }
        ble.onUnexpectedDisconnect = { [weak self] in
            Task { @MainActor in self?.scheduleReconnect() }
        }
        UserDefaults.standard.register(defaults: ["autoConnect": true, "autoReconnect": true])
        Task { [weak self] in
            guard UserDefaults.standard.bool(forKey: "autoConnect") else { return }
            self?.connect()
        }
    }

    func connect() {
        guard !phase.isRunning else { return }
        reconnectTask?.cancel()
        reconnectTask = nil
        Task { await runConnectChain() }
    }

    func disconnect() {
        guard !phase.isRunning else { return }
        reconnectTask?.cancel()
        reconnectTask = nil
        reconnectAttempts = 0
        Task { await runDisconnectChain() }
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
            try await ble.ensurePoweredOn()
            try await ble.connect(timeout: AppConfig.scanTimeout)
            if previousSSID == nil {
                let currentSSID = await HotspotJoiner.currentSSID()
                if currentSSID != AppConfig.hotspotSSID { previousSSID = currentSSID }
            }
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
            note("热点链路已验证：\(verification.wifiInterface)，网关 \(verification.gateway)，直连互联网 \(verification.internetReachable ? "可达" : "不可达（Clash TUN/运营商网络请分别验收）")")
        } catch {
            phase = .failed(error.localizedDescription)
            note("失败：\(error.localizedDescription)")
            if !(error is WiFiAccessError) { scheduleReconnect() }
        }
    }

    private func runDisconnectChain() async {
        do {
            phase = .bleSearching
            try await ble.ensurePoweredOn()
            try await ble.connect(timeout: AppConfig.scanTimeout)
            _ = try await ble.send(BleProtocol.cmdDisconnect,
                                   expectingHotspotOn: false,
                                   timeout: AppConfig.hotspotTimeout)
            ble.disconnect()
            phase = .idle
            if let ssid = previousSSID {
                try await HotspotJoiner.join(ssid: ssid, password: "")
                previousSSID = nil
                note("手机热点已关闭，正在恢复之前的 Wi-Fi：\(ssid)")
            } else {
                note("手机热点已关闭；没有检测到此前的 Wi-Fi 网络")
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
        guard UserDefaults.standard.bool(forKey: "autoReconnect"),
              reconnectTask == nil,
              !phase.isRunning,
              reconnectAttempts < 5 else { return }
        let delays: [UInt64] = [3, 8, 15, 30, 60]
        let delay = delays[reconnectAttempts]
        reconnectAttempts += 1
        note("连接中断，\(delay) 秒后自动重连（\(reconnectAttempts)/5）")
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delay * 1_000_000_000)
            guard !Task.isCancelled, let self else { return }
            self.reconnectTask = nil
            self.connect()
        }
    }
}
