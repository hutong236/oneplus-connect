import XCTest
@testable import OnePlusConnect

@MainActor
final class AppStateTests: XCTestCase {
    func testDisconnectLeavesNetworkSelectionToMacOS() async throws {
        for closeHotspot in [false, true] {
            var left = false
            let wifi = WiFiSession(leaveHotspot: { left = true })
            let state = AppState(ble: TestBLE(), defaults: preferences(), wifi: wifi)
            state.disconnect(closeHotspot: closeHotspot)
            try await Task.sleep(nanoseconds: 50_000_000)
            XCTAssertTrue(left)
            XCTAssertEqual(state.phase, .idle)
        }
    }

    private func preferences() -> UserDefaults {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        defaults.set(false, forKey: "autoConnect")
        defaults.set(true, forKey: "autoReconnect")
        return defaults
    }

    private func wifi() -> WiFiSession {
        WiFiSession(leaveHotspot: {})
    }

    func testDisconnectCanLeaveHotspotRunningWithoutBluetoothAvailable() async throws {
        let ble = TestBLE()
        ble.unavailable = true
        let state = AppState(ble: ble, defaults: preferences(), wifi: wifi())
        state.disconnect(closeHotspot: false)
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(state.phase, .idle)
        XCTAssertEqual(ble.commands, [])
        XCTAssertTrue(ble.released)
    }

    func testDisconnectClosesHotspotWhenRequested() async throws {
        let ble = TestBLE()
        let state = AppState(ble: ble, defaults: preferences(), wifi: wifi())
        state.disconnect(closeHotspot: true)
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(state.phase, .idle)
        XCTAssertEqual(ble.commands, [0x11])
        XCTAssertTrue(ble.released)
        XCTAssertFalse(state.hotspotOn)
    }


    func testDisconnectLeavesHotspotWiFi() async throws {
        var left = false
        let wifi = WiFiSession(leaveHotspot: { left = true })
        let state = AppState(ble: TestBLE(), defaults: preferences(), wifi: wifi)
        state.disconnect(closeHotspot: false)
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertTrue(left)
        XCTAssertEqual(state.phase, .idle)
    }

    func testDisablingReconnectCancelsQueuedAttemptEvenAfterReenabling() async throws {
        let ble = TestBLE()
        let state = AppState(ble: ble, defaults: preferences(), wifi: wifi())
        ble.onUnexpectedDisconnect?()
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertTrue(state.log.contains { $0.contains("1/5") })
        let logCount = state.log.count
        state.setAutoReconnect(false)
        state.setAutoReconnect(true)
        try await Task.sleep(nanoseconds: 3_200_000_000)
        XCTAssertEqual(state.phase, .idle)
        XCTAssertEqual(state.log.count, logCount)
    }

    func testImmediatePreferenceChangeDoesNotReviveOldDisconnectEvent() async throws {
        let ble = TestBLE()
        let state = AppState(ble: ble, defaults: preferences(), wifi: wifi())
        ble.onUnexpectedDisconnect?()
        state.setAutoReconnect(false)
        state.setAutoReconnect(true)
        let count = state.log.count
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(state.log.count, count)
        state.setAutoReconnect(false)
    }
    func testFailureLeavingWiFiStillReportsHotspotClosed() async throws {
        let ble = TestBLE()
        let wifi = WiFiSession(leaveHotspot: { throw BleError.timeout("Wi-Fi unavailable") })
        let state = AppState(ble: ble, defaults: preferences(), wifi: wifi)
        ble.onStatus?(BleProtocol.Status(hotspotOn: true, upstreamOk: true,
                                         cmdFailed: false, batteryPercent: 90, ssid: "mmmmmm"))
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertTrue(state.hotspotOn)
        state.disconnect(closeHotspot: true)
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertFalse(state.hotspotOn)
        XCTAssertTrue(ble.released)
        XCTAssertTrue(state.phase.label.contains("热点已关闭"))
        XCTAssertFalse(state.phase.label.hasPrefix("失败："))
    }
}

@MainActor
private final class TestBLE: BleConnection {
    var onStatus: ((BleProtocol.Status) -> Void)?
    var onUnexpectedDisconnect: (() -> Void)?
    var unavailable = false
    var commands: [UInt8] = []
    var released = false

    func ensurePoweredOn(timeout: TimeInterval) async throws {
        if unavailable { throw BleError.bluetoothUnavailable }
    }

    func connect(timeout: TimeInterval) async throws {}

    func send(_ cmd: UInt8, expectingHotspotOn expected: Bool?,
              timeout: TimeInterval) async throws -> BleProtocol.Status {
        commands.append(cmd)
        return BleProtocol.parseStatus(Data([2, expected == true ? 1 : 0, 90, 0]))!
    }

    func disconnect() { released = true }
}
