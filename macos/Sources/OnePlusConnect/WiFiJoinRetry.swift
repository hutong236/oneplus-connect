import Foundation

enum WiFiJoinRetry {
    static func run(attempt: () async throws -> String,
                    pause: () async throws -> Void = { try await Task.sleep(nanoseconds: 2_000_000_000) }) async throws -> String {
        for index in 0..<4 {
            try Task.checkCancellation()
            let output = try await attempt()
            guard WiFiOutput.networkNotFound(output), index < 3 else { return output }
            try await pause()
        }
        preconditionFailure("Retry loop must return on its final attempt")
    }
}
