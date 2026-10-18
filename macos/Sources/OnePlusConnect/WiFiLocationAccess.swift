import CoreLocation
import AppKit
import Foundation

enum WiFiAccessError: LocalizedError {
    case configuration(String)

    var errorDescription: String? {
        switch self {
        case .configuration(let message): return message
        }
    }
}

@MainActor
final class WiFiLocationAccess: NSObject, CLLocationManagerDelegate {
    static let shared = WiFiLocationAccess()

    private let manager = CLLocationManager()
    private var pending: (id: UUID, continuation: CheckedContinuation<Void, Error>)?

    override init() {
        super.init()
        manager.delegate = self
    }

    func ensureAuthorized() async throws {
        guard Bundle.main.bundleURL.pathExtension == "app",
              Bundle.main.object(forInfoDictionaryKey: "NSLocationUsageDescription") != nil else {
            throw WiFiAccessError.configuration("读取 Wi-Fi 名称需要位置权限。请在仓库根目录运行 bash script/build_and_run.sh 启动应用，再允许位置访问。")
        }
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse: return
        case .denied, .restricted:
            throw permissionDenied()
        case .notDetermined: break
        @unknown default: throw permissionDenied()
        }
        guard pending == nil else { throw BleError.busy }
        let requestID = UUID()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            pending = (requestID, continuation)
            NSApp.activate(ignoringOtherApps: true)
            manager.requestWhenInUseAuthorization()
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                guard let self, let request = self.pending, request.id == requestID else { return }
                self.pending = nil
                request.continuation.resume(throwing: self.permissionDenied())
            }
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor [weak self] in self?.authorizationDidChange() }
    }

    private func authorizationDidChange() {
        guard manager.authorizationStatus != .notDetermined, let request = pending else { return }
        pending = nil
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            request.continuation.resume()
        default:
            request.continuation.resume(throwing: permissionDenied())
        }
    }

    private func permissionDenied() -> WiFiAccessError {
        .configuration("请在系统设置 → 隐私与安全性 → 定位服务中，开启定位服务并允许 OnePlus Connect 访问位置，以读取实际 Wi-Fi 名称。")
    }
}
