import XCTest
@testable import OnePlusConnect

final class WiFiOutputTests: XCTestCase {
    func testRedactedSSIDIsNotAnActualNetwork() {
        XCTAssertNil(WiFiOutput.visibleSSID("<redacted>"))
        XCTAssertNil(WiFiOutput.visibleSSID("  <REDACTED>\n"))
        XCTAssertNil(WiFiOutput.visibleSSID(nil))
        XCTAssertNil(WiFiOutput.visibleSSID("  "))
        XCTAssertEqual(WiFiOutput.visibleSSID(" mmmmmm\n"), "mmmmmm")
    }

    func testExitZeroNetworksetupErrorsAreFailures() {
        XCTAssertNotNil(WiFiOutput.joinFailure("Failed to join network mmmmmm.\nError: -3900\n"))
        XCTAssertNotNil(WiFiOutput.joinFailure("Could not find network mmmmmm."))
        XCTAssertNotNil(WiFiOutput.joinFailure("Error joining network mmmmmm.\n"))
        XCTAssertNil(WiFiOutput.joinFailure(""))
    }

    @MainActor
    func testUnbundledLaunchGivesInstructionsBeforeRequestingLocation() async {
        do {
            try await WiFiLocationAccess.shared.ensureAuthorized()
            XCTFail("An unbundled executable cannot request the app's location authorization")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("script/build_and_run.sh"))
        }
    }
}
