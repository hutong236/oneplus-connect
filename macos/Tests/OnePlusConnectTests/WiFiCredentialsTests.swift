import XCTest
@testable import OnePlusConnect

final class WiFiCredentialsTests: XCTestCase {
    func testSavedAirportPasswordUsesActualKeychainDescription() async {
        let password = await HotspotJoiner.keychainWifiPassword(ssid: "mmmmmm", appPassword: { _ in nil }, query: { arguments in
            guard arguments == ["find-generic-password", "-D", "AirPort network password", "-a", "mmmmmm", "-w"] else {
                throw NSError(domain: "test-keychain", code: 44)
            }
            return "test-network-password\n"
        })
        XCTAssertEqual(password, "test-network-password")
    }

    func testAppPasswordTakesPriorityWithoutSystemQuery() async {
        let password = await HotspotJoiner.keychainWifiPassword(ssid: "mmmmmm", appPassword: { _ in "app-password" }, query: { _ in
            XCTFail("System keychain must not be queried when app credentials exist")
            return ""
        })
        XCTAssertEqual(password, "app-password")
    }
}
