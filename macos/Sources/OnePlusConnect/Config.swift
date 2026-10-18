import Foundation

/// 端上配置。sharedSecret 必须与 Android 端 AgentConfig.SHARED_SECRET 一致。
enum AppConfig {
    static let sharedSecret = "change-me-oneplus-connect"

    /// 手机热点 SSID
    static let hotspotSSID = "mmmmmm"

    /// Wi-Fi 密码。强烈建议填写：
    /// - 填写后可用 networksetup 强制从其他 Wi-Fi 切换到热点（自动加入做不到跨网切换）
    /// - 留空则依赖「已知网络自动加入」（仅当 Mac 当前无 Wi-Fi 时有效）
    /// 注：新版 macOS 的 Wi-Fi 密码不在登录钥匙串（security CLI 查不到），别指望它能取到
    static let wifiPassword = ""

    static let scanTimeout: TimeInterval = 10
    static let hotspotTimeout: TimeInterval = 15
    static let joinTimeout: TimeInterval = 25
}
