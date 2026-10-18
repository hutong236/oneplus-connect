import Foundation

@MainActor
final class WiFiSession {
    private let leaveHotspot: () async throws -> Void

    init(leaveHotspot: @escaping () async throws -> Void = HotspotJoiner.leaveHotspot) {
        self.leaveHotspot = leaveHotspot
    }

    func disconnect() async throws {
        try await leaveHotspot()
    }
}
