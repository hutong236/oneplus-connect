package com.hutong.oneplusagent

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import com.hutong.oneplusagent.service.AgentForegroundService
import android.util.Log

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED) return
        try {
            // Android 11 允许从 BOOT_COMPLETED 启动 connectedDevice 前台服务
            context.startForegroundService(Intent(context, AgentForegroundService::class.java))
        } catch (t: Throwable) {
            Log.w("OnePlusAgent", "开机自启失败: $t")
        }
    }
}
