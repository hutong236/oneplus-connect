package com.hutong.oneplusagent

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import com.hutong.oneplusagent.service.AgentForegroundService

/**
 * 调试通道：允许 adb 触发与 BLE 完全相同的指令分发路径。
 * 仅限开发验证使用，发布前移除或加签名校验。
 *
 * adb shell am broadcast -a com.hutong.oneplusagent.DEBUG_CMD --ei cmd 16
 *   cmd: 1=PING  16=CONNECT(开热点)  17=DISCONNECT(关热点)  32=GET_STATUS
 */
class DebugCommandReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        android.util.Log.i("OnePlusAgent", "DebugCommandReceiver 收到广播 action=${intent.action}")
        if (intent.action != ACTION) return
        val cmd = intent.getIntExtra("cmd", -1)
        if (cmd !in listOf(1, 16, 17, 32)) return
        android.util.Log.i("OnePlusAgent", "DebugCommandReceiver 转发指令 cmd=0x%02x".format(cmd))
        val service = Intent(context, AgentForegroundService::class.java)
            .putExtra("cmd", cmd)
        context.startForegroundService(service)
    }

    companion object {
        const val ACTION = "com.hutong.oneplusagent.DEBUG_CMD"
    }
}
