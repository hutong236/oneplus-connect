package com.hutong.oneplusagent.core

/**
 * 端上配置。SHARED_SECRET 必须与 macOS 端 AppConfig.sharedSecret 一致，
 * 修改任一端后需同步另一端并重装/重启。
 */
object AgentConfig {
    const val SHARED_SECRET = "change-me-oneplus-connect"
    const val HOTSPOT_SSID = "mmmmmm"
    const val DEVICE_NAME = "OnePlus Agent"

    /** 热点开启确认的轮询上限（毫秒） */
    const val HOTSPOT_POLL_TIMEOUT_MS = 10_000L
    const val HOTSPOT_POLL_INTERVAL_MS = 500L
}
