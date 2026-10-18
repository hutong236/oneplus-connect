import Foundation
import Security

/// 端上配置。BLE 密钥从 macOS Keychain 读取。
enum AppConfig {
    static var sharedSecret: String {
        keychainSecret(account: "ble-shared-secret") ?? ""
    }

    static func savedWiFiPassword(ssid: String) -> String? {
        keychainSecret(account: "wifi-password:\(ssid)")
    }

    private static func keychainSecret(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.hutong.oneplusconnect",
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// 手机热点 SSID
    static let hotspotSSID = "mmmmmm"

    /// Wi-Fi 密码。强烈建议填写：
    /// - 填写后可用 networksetup 强制从其他 Wi-Fi 切换到热点（自动加入做不到跨网切换）
    /// - 留空则依赖「已知网络自动加入」（仅当 Mac 当前无 Wi-Fi 时有效）
    /// 系统密码读取可能需要钥匙串授权；应用专用条目优先。
    static let wifiPassword = ""

    static let scanTimeout: TimeInterval = 10
    static let hotspotTimeout: TimeInterval = 15
    static let joinTimeout: TimeInterval = 45
}
