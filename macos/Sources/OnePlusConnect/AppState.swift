import Foundation
import SwiftUI

/// 状态机与主链路编排：BLE 连接 → 指令开热点 → 加入 Wi-Fi → 连通性验证
@MainActor
final class AppState: ObservableObject {

    enum Phase: Equatable {
        case idle
        case bleSearching
        case hotspotStarting
        case joiningWifi
        case verifying
        case connected(gateway: String)
        case failed(String)

        var isRunning: Bool {
            switch self {
            case .bleSearching, .hotspotStarting, .joiningWifi, .verifying: return true
            default: return false
            }
        }

        var label: String {
            switch self {
            case .idle: return "未连接"
            case .bleSearching: return "正在搜索 OnePlus 6T …"
            case .hotspotStarting: return "BLE 已连接，正在开启手机热点 …"
            case .joiningWifi: return "热点已开启，正在加入 Wi-Fi …"
            case .verifying: return "验证网络连通性 …"
            case .connected(let gateway): return "已连接（网关 \(gateway)）"
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
    }

    func connect() {
        guard !phase.isRunning else { return }
        Task { await runConnectChain() }
    }

    func disconnect() {
        guard !phase.isRunning else { return }
        Task { await runDisconnectChain() }
    }

    private func runConnectChain() async {
        do {
            phase = .bleSearching
            note("搜索 OnePlus Agent 广播 …")
            try await ble.ensurePoweredOn()
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
            // 入网命令失败不直接判死：系统自动加入/已在网也算数，交由连通性轮询裁决
            do {
                try await HotspotJoiner.join(ssid: ssid, password: AppConfig.wifiPassword)
            } catch {
                note("networksetup 返回：\(error.localizedDescription)（继续验证实际状态）")
            }

            phase = .verifying
            let gateway = try await ConnectivityCheck.waitUntilOnline(ssid: ssid,
                                                                      timeout: AppConfig.joinTimeout)
            phase = .connected(gateway: gateway)
            note("连接完成，网关 \(gateway)")
        } catch {
            phase = .failed(error.localizedDescription)
            note("失败：\(error.localizedDescription)")
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
            note("已断开（手机热点已关闭）")
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
}
