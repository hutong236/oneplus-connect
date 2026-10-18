import XCTest
@testable import OnePlusConnect

final class WiFiJoinRetryTests: XCTestCase {
    func testNewHotspotBecomesVisibleAfterTwoFailedScans() async throws {
        var attempts = 0
        var pauses = 0
        let output = try await WiFiJoinRetry.run(attempt: {
            attempts += 1
            return attempts < 3 ? "Could not find network mmmmmm." : ""
        }, pause: { pauses += 1 })
        XCTAssertEqual(output, "")
        XCTAssertEqual(attempts, 3)
        XCTAssertEqual(pauses, 2)
    }

    func testUnavailableNetworkStopsAfterFourAttempts() async throws {
        var attempts = 0
        let output = try await WiFiJoinRetry.run(attempt: {
            attempts += 1
            return "Could not find network mmmmmm."
        }, pause: {})
        XCTAssertEqual(attempts, 4)
        XCTAssertNotNil(WiFiOutput.joinFailure(output))
    }

    func testWrongPasswordDoesNotRetry() async throws {
        var attempts = 0
        let output = try await WiFiJoinRetry.run(attempt: {
            attempts += 1
            return "Failed to join network: authentication error."
        }, pause: { XCTFail("Authentication errors must not be retried") })
        XCTAssertEqual(attempts, 1)
        XCTAssertNotNil(WiFiOutput.joinFailure(output))
    }

    func testCancellationDuringDelayStopsRetries() async throws {
        var attempts = 0
        do {
            _ = try await WiFiJoinRetry.run(attempt: {
                attempts += 1
                return "Could not find network mmmmmm."
            }, pause: { throw CancellationError() })
            XCTFail("Cancellation must propagate")
        } catch is CancellationError {
            XCTAssertEqual(attempts, 1)
        }
    }
}
