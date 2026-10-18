import Foundation

enum WiFiOutput {
    static func networkNotFound(_ output: String) -> Bool {
        let value = output.lowercased()
        return value.contains("could not find network") || value.contains("找不到网络")
    }

    static func visibleSSID(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed.lowercased() == "<redacted>" ? nil : trimmed
    }

    static func joinFailure(_ output: String) -> String? {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercased = trimmed.lowercased()
        let failureMarkers = ["failed", "error", "could not", "not associated", "失败", "错误", "找不到"]
        return failureMarkers.contains(where: lowercased.contains) ? trimmed : nil
    }
}
