import Foundation

/// 端上配置。sharedSecret 必须与 Android 端 AgentConfig.SHARED_SECRET 一致。
enum AppConfig {
    static let sharedSecret = "change-me-oneplus-connect"

    /// 手机热点 SSID
    static let hotspotSSID = "mmmmmm"

    /// Wi-Fi 密码。留空表示依赖钥匙串中已保存的密码（本机曾连过 mmmmmm 即可）
    static let wifiPassword = ""

    static let scanTimeout: TimeInterval = 10
    static let hotspotTimeout: TimeInterval = 15
    static let joinTimeout: TimeInterval = 25
}
