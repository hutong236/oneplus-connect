package com.hutong.oneplusagent.core

import android.content.Context

/**
 * 端上配置。共享密钥通过应用界面录入，并只加密保存在 Android Keystore。
 */
object AgentConfig {
    const val HOTSPOT_SSID = "mmmmmm"
    const val DEVICE_NAME = "OnePlus Agent"

    /** 热点开启确认的轮询上限（毫秒） */
    const val HOTSPOT_POLL_TIMEOUT_MS = 10_000L
    const val HOTSPOT_POLL_INTERVAL_MS = 500L

    fun sharedSecret(context: Context): String = BleSecretStore.read(context)
}
