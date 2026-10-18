import XCTest
@testable import OnePlusConnect

final class InternetReachabilityTests: XCTestCase {
    func testInternetProbeUsesSystemRouteForTUNCompatibility() async {
        let reachable = await ConnectivityCheck.internetReachable(execute: { path, arguments, _ in
            XCTAssertEqual(path, "/usr/bin/curl")
            XCTAssertFalse(arguments.contains("--interface"), "Internet traffic must follow the configured system route")
            XCTAssertFalse(arguments.contains("--noproxy"), "Probe must not override configured proxy behavior")
            return "200"
        })
        XCTAssertTrue(reachable)
    }

    func testRedirectIsNotAcceptedAsInternetSuccess() async {
        let reachable = await ConnectivityCheck.internetReachable(execute: { _, _, _ in "302" })
        XCTAssertFalse(reachable)
    }

    func testProbeFailureIsNotPresentedAsProofOfNoInternet() {
        let label = AppState.Phase.connected(gateway: "192.168.1.1", internetReachable: false).label
        XCTAssertTrue(label.contains("探测未通过"))
        XCTAssertFalse(label.contains("不可直连"))
    }
}
