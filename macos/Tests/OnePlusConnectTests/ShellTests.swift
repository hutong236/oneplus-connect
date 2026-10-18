import XCTest
@testable import OnePlusConnect

final class ShellTests: XCTestCase {
    func testSuccessfulProcessReturnsOutput() async throws {
        let output = try await Shell.run("/usr/bin/printf", ["hello"])
        XCTAssertEqual(output, "hello")
    }

    func testNonzeroExitPreservesDiagnostic() async throws {
        do {
            _ = try await Shell.run("/bin/sh", ["-c", "printf diagnostic; exit 7"])
            XCTFail("Expected a process error")
        } catch let error as Shell.ShellError {
            XCTAssertEqual(error.code, 7)
            XCTAssertEqual(error.output, "diagnostic")
        }
    }

    func testTimeoutTerminatesProcessAndThrows() async throws {
        do {
            _ = try await Shell.run("/bin/sleep", ["5"], timeout: 0.05)
            XCTFail("Expected a timeout")
        } catch let error as Shell.ShellError {
            XCTAssertEqual(error.code, -1)
            XCTAssertTrue(error.output.contains("超时"))
        }
    }

    func testConcurrentProcessesReturnTheirOwnOutputs() async throws {
        let outputs = try await withThrowingTaskGroup(of: String.self) { group in
            for index in 0..<5 {
                group.addTask { try await Shell.run("/usr/bin/printf", [String(index)]) }
            }
            var collected: [String] = []
            for try await output in group { collected.append(output) }
            return collected.sorted()
        }
        XCTAssertEqual(outputs, ["0", "1", "2", "3", "4"])
    }
}
