import CryptoKit
import CoreBluetooth
import Foundation

/// BLE 协议 v1，契约见 docs/ble-protocol.md。
/// 修改本文件必须同步 Android 端 BleProtocol.kt。
enum BleProtocol {
    static let version: UInt8 = 1

    static let serviceUUID = CBUUID(string: "7b6e0001-2a4c-4e6d-9b8a-5f1e3d5c7a9b")
    static let cmdUUID = CBUUID(string: "7b6e0002-2a4c-4e6d-9b8a-5f1e3d5c7a9b")
    static let statusUUID = CBUUID(string: "7b6e0003-2a4c-4e6d-9b8a-5f1e3d5c7a9b")

    static let cmdPing: UInt8 = 0x01
    static let cmdConnect: UInt8 = 0x10
    static let cmdDisconnect: UInt8 = 0x11
    static let cmdGetStatus: UInt8 = 0x20

    static let flagHotspotOn: UInt8 = 0x01
    static let flagUpstreamOk: UInt8 = 0x02
    static let flagCmdFailed: UInt8 = 0x04

    static let batteryUnknown: UInt8 = 0xFF

    struct Status: Equatable {
        var hotspotOn: Bool
        var upstreamOk: Bool
        var cmdFailed: Bool
        var batteryPercent: Int?
        var ssid: String?
    }

    /// CMD 帧（14 字节）：ver(1) cmd(1) nonce(4 LE) auth(8)
    /// auth = SHA256(secret ‖ nonce_le ‖ cmd)[0..7]
    static func encodeCommand(_ cmd: UInt8, secret: String) -> Data {
        let nonce = UInt32.random(in: 1...UInt32.max)
        var input = Data(secret.utf8)
        withUnsafeBytes(of: nonce.littleEndian) { input.append(contentsOf: $0) }
        input.append(cmd)
        let digest = SHA256.hash(data: input)

        var frame = Data()
        frame.append(version)
        frame.append(cmd)
        withUnsafeBytes(of: nonce.littleEndian) { frame.append(contentsOf: $0) }
        frame.append(contentsOf: digest.prefix(8))
        return frame
    }

    /// STATUS 帧：ver(1) flags(1) battery(1) ssidLen(1) ssid(N)
    static func parseStatus(_ data: Data) -> Status? {
        guard data.count >= 4 else { return nil }
        let bytes = [UInt8](data)
        guard bytes[0] == version else { return nil }
        let flags = bytes[1]
        let battery = bytes[2]
        let ssidLen = Int(bytes[3])
        guard data.count >= 4 + ssidLen else { return nil }
        let ssid = String(bytes: bytes[4..<(4 + ssidLen)], encoding: .utf8)
        return Status(
            hotspotOn: flags & flagHotspotOn != 0,
            upstreamOk: flags & flagUpstreamOk != 0,
            cmdFailed: flags & flagCmdFailed != 0,
            batteryPercent: battery == batteryUnknown ? nil : Int(battery),
            ssid: (ssid?.isEmpty == true) ? nil : ssid
        )
    }
}
