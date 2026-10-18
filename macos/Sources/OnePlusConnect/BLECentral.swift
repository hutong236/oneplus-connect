import CoreBluetooth
import Foundation

enum BleError: LocalizedError, Equatable {
    case bluetoothUnavailable
    case deviceNotFound
    case connectFailed(String)
    case timeout(String)
    case busy

    var errorDescription: String? {
        switch self {
        case .bluetoothUnavailable: return "Mac 蓝牙不可用或未开启"
        case .deviceNotFound: return "未发现 OnePlus Agent 广播（手机端服务是否已启动？）"
        case .connectFailed(let m): return "BLE 连接失败：\(m)"
        case .timeout(let m): return "超时：\(m)"
        case .busy: return "上一次操作仍在进行中"
        }
    }
}

/// BLE 中心设备：扫描 → 连接 → 发现特征 → 订阅状态 → 写指令。
/// 所有公开 async 方法串行使用（AppState 主线程调用）。
@MainActor
protocol BleConnection: AnyObject {
    var onStatus: ((BleProtocol.Status) -> Void)? { get set }
    var onUnexpectedDisconnect: (() -> Void)? { get set }
    func ensurePoweredOn(timeout: TimeInterval) async throws
    func connect(timeout: TimeInterval) async throws
    func send(_ cmd: UInt8, expectingHotspotOn expected: Bool?,
              timeout: TimeInterval) async throws -> BleProtocol.Status
    func disconnect()
}

@MainActor
final class BleCentral: NSObject, BleConnection {
    enum Phase: Equatable {
        case idle, scanning, connecting, discovering, ready, disconnected
    }

    var onPhaseChange: ((Phase) -> Void)?
    var onStatus: ((BleProtocol.Status) -> Void)?
    var onUnexpectedDisconnect: (() -> Void)?

    private var manager: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var cmdCharacteristic: CBCharacteristic?
    private var statusCharacteristic: CBCharacteristic?

    private var bootContinuation: CheckedContinuation<Void, Error>?
    private var connectContinuation: CheckedContinuation<Void, Error>?

    private final class PendingCommand {
        let cmd: UInt8
        let expectHotspotOn: Bool?
        let continuation: CheckedContinuation<BleProtocol.Status, Error>
        var workItem: DispatchWorkItem?
        init(cmd: UInt8, expectHotspotOn: Bool?,
             continuation: CheckedContinuation<BleProtocol.Status, Error>) {
            self.cmd = cmd
            self.expectHotspotOn = expectHotspotOn
            self.continuation = continuation
        }
    }

    private var pendingCommand: PendingCommand?
    private var suppressDisconnectCallback = false

    private(set) var phase: Phase = .idle {
        didSet {
            onPhaseChange?(phase)
        }
    }

    func ensurePoweredOn(timeout: TimeInterval = 5) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            DispatchQueue.main.async {
                if self.manager == nil {
                    self.manager = CBCentralManager(delegate: self, queue: .main)
                }
                if self.manager?.state == .poweredOn {
                    cont.resume()
                    return
                }
                guard self.bootContinuation == nil else {
                    cont.resume(throwing: BleError.busy)
                    return
                }
                self.bootContinuation = cont
                DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
                    if let c = self.bootContinuation {
                        self.bootContinuation = nil
                        c.resume(throwing: BleError.bluetoothUnavailable)
                    }
                }
            }
        }
    }

    /// 已就绪时直接返回，否则扫描并完成整套连接 + 特征发现 + 订阅
    func connect(timeout: TimeInterval) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            DispatchQueue.main.async {
                if let p = self.peripheral, p.state == .connected,
                   self.cmdCharacteristic != nil, self.statusCharacteristic != nil {
                    self.phase = .ready
                    cont.resume()
                    return
                }
                guard self.connectContinuation == nil else {
                    cont.resume(throwing: BleError.busy)
                    return
                }
                guard let manager = self.manager, manager.state == .poweredOn else {
                    cont.resume(throwing: BleError.bluetoothUnavailable)
                    return
                }
                self.connectContinuation = cont
                self.phase = .scanning
                manager.scanForPeripherals(withServices: [BleProtocol.serviceUUID],
                                           options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
                DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
                    if let c = self.connectContinuation {
                        self.connectContinuation = nil
                        self.manager?.stopScan()
                        c.resume(throwing: BleError.deviceNotFound)
                    }
                }
            }
        }
    }

    /// 发送指令并等待符合预期的 STATUS 通知（expected 为 nil 表示任意状态即可）
    func send(_ cmd: UInt8, expectingHotspotOn expected: Bool?,
              timeout: TimeInterval) async throws -> BleProtocol.Status {
        guard AppConfig.sharedSecret.utf8.count >= 32 else {
            throw BleError.connectFailed("未配置 BLE 配对密钥，请按配对说明设置 Keychain")
        }
        guard let peripheral = peripheral, let characteristic = cmdCharacteristic else {
            throw BleError.connectFailed("BLE 未就绪")
        }
        return try await withCheckedThrowingContinuation { cont in
            DispatchQueue.main.async {
                guard self.pendingCommand == nil else {
                    cont.resume(throwing: BleError.busy)
                    return
                }
                let pending = PendingCommand(cmd: cmd, expectHotspotOn: expected, continuation: cont)
                let item = DispatchWorkItem {
                    if let p = self.pendingCommand {
                        self.pendingCommand = nil
                        p.continuation.resume(throwing: BleError.timeout(
                            String(format: "等待指令 0x%02X 结果超时（%.0fs）", cmd, timeout)))
                    }
                }
                pending.workItem = item
                self.pendingCommand = pending
                DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: item)
                peripheral.writeValue(BleProtocol.encodeCommand(cmd, secret: AppConfig.sharedSecret),
                                      for: characteristic, type: .withResponse)
            }
        }
    }

    func disconnect() {
        DispatchQueue.main.async {
            self.suppressDisconnectCallback = true
            if let p = self.peripheral {
                self.manager?.cancelPeripheralConnection(p)
            } else {
                self.suppressDisconnectCallback = false
            }
            self.peripheral = nil
            self.cmdCharacteristic = nil
            self.statusCharacteristic = nil
            self.phase = .idle
        }
    }

    private func failPendingCommand(_ error: Error) {
        if let p = pendingCommand {
            pendingCommand = nil
            p.workItem?.cancel()
            p.continuation.resume(throwing: error)
        }
    }
}

extension BleCentral: @preconcurrency CBCentralManagerDelegate, @preconcurrency CBPeripheralDelegate {

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn, let cont = bootContinuation {
            bootContinuation = nil
            cont.resume()
        }
        if central.state == .poweredOff || central.state == .unsupported {
            if let cont = bootContinuation {
                bootContinuation = nil
                cont.resume(throwing: BleError.bluetoothUnavailable)
            }
            failPendingCommand(BleError.bluetoothUnavailable)
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard connectContinuation != nil else { return }
        central.stopScan()
        self.peripheral = peripheral
        peripheral.delegate = self
        phase = .connecting
        central.connect(peripheral, options: nil)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        phase = .discovering
        peripheral.discoverServices([BleProtocol.serviceUUID])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral,
                        error: Error?) {
        phase = .disconnected
        if let cont = connectContinuation {
            connectContinuation = nil
            cont.resume(throwing: BleError.connectFailed(error?.localizedDescription ?? "未知"))
        }
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral,
                        error: Error?) {
        let wasUnexpected = !suppressDisconnectCallback
        suppressDisconnectCallback = false
        phase = .disconnected
        cmdCharacteristic = nil
        statusCharacteristic = nil
        if let cont = connectContinuation {
            connectContinuation = nil
            cont.resume(throwing: BleError.connectFailed("连接中断"))
        }
        failPendingCommand(BleError.connectFailed("连接中断"))
        if wasUnexpected {
            onUnexpectedDisconnect?()
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil, let service = peripheral.services?.first(where: { $0.uuid == BleProtocol.serviceUUID }) else {
            if let cont = connectContinuation {
                connectContinuation = nil
                cont.resume(throwing: BleError.connectFailed("未找到目标 Service"))
            }
            return
        }
        peripheral.discoverCharacteristics([BleProtocol.cmdUUID, BleProtocol.statusUUID], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService,
                    error: Error?) {
        guard error == nil else {
            if let cont = connectContinuation {
                connectContinuation = nil
                cont.resume(throwing: BleError.connectFailed("特征发现失败"))
            }
            return
        }
        for ch in service.characteristics ?? [] {
            if ch.uuid == BleProtocol.cmdUUID {
                cmdCharacteristic = ch
            } else if ch.uuid == BleProtocol.statusUUID {
                statusCharacteristic = ch
            }
        }
        guard let status = statusCharacteristic else {
            if let cont = connectContinuation {
                connectContinuation = nil
                cont.resume(throwing: BleError.connectFailed("未找到 STATUS 特征"))
            }
            return
        }
        peripheral.setNotifyValue(true, for: status)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic,
                    error: Error?) {
        guard characteristic.uuid == BleProtocol.statusUUID else { return }
        if error == nil {
            phase = .ready
            if let cont = connectContinuation {
                connectContinuation = nil
                cont.resume()
            }
        } else if let cont = connectContinuation {
            connectContinuation = nil
            cont.resume(throwing: BleError.connectFailed("订阅状态失败：\(error!.localizedDescription)"))
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        guard characteristic.uuid == BleProtocol.statusUUID, error == nil,
              let data = characteristic.value,
              let status = BleProtocol.parseStatus(data) else { return }

        onStatus?(status)

        if let pending = pendingCommand,
           pending.expectHotspotOn == nil || pending.expectHotspotOn == status.hotspotOn {
            pendingCommand = nil
            pending.workItem?.cancel()
            pending.continuation.resume(returning: status)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        guard characteristic.uuid == BleProtocol.cmdUUID, let error = error else { return }
        failPendingCommand(BleError.connectFailed("指令写入失败：\(error.localizedDescription)"))
    }
}
