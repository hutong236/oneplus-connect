package com.hutong.oneplusagent

import android.annotation.SuppressLint
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.widget.Button
import android.widget.TextView
import com.hutong.oneplusagent.hotspot.HotspotController
import com.hutong.oneplusagent.service.AgentForegroundService
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class MainActivity : Activity() {

    private lateinit var logView: TextView
    private lateinit var statusView: TextView
    private lateinit var hotspot: HotspotController
    private val timeFmt = SimpleDateFormat("HH:mm:ss", Locale.US)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        hotspot = HotspotController(this)
        logView = findViewById(R.id.log)
        statusView = findViewById(R.id.status)

        findViewById<Button>(R.id.btnStartService).setOnClickListener { startAgent() }
        findViewById<Button>(R.id.btnStopService).setOnClickListener {
            stopService(Intent(this, AgentForegroundService::class.java))
            appendLog("后台服务已停止")
        }
        findViewById<Button>(R.id.btnTestOn).setOnClickListener {
            appendLog("手动测试：开启热点")
            hotspot.enable { appendLog("结果：$it") }
        }
        findViewById<Button>(R.id.btnTestOff).setOnClickListener {
            appendLog("手动测试：关闭热点")
            hotspot.disable { appendLog("结果：$it") }
        }
        findViewById<Button>(R.id.btnOpenSettings).setOnClickListener {
            runCatching { startActivity(Intent("android.settings.TETHER_SETTINGS")) }
        }

        requestRuntimePermissions()
        refreshStatus()
        handleDebugIntent(intent)
    }

    override fun onNewIntent(intent: Intent?) {
        super.onNewIntent(intent)
        handleDebugIntent(intent)
    }

    /** 调试入口：adb shell am start -n .MainActivity --ei cmd 16（Activity 前台路径，绕过后台冻结） */
    private fun handleDebugIntent(intent: Intent?) {
        val cmd = intent?.getIntExtra("cmd", -1) ?: -1
        if (cmd == -1) return
        android.util.Log.i("OnePlusAgent", "Activity 收到调试指令 cmd=0x%02x".format(cmd))
        appendLog("调试指令 0x%02x".format(cmd))
        startForegroundService(
            Intent(this, com.hutong.oneplusagent.service.AgentForegroundService::class.java)
                .putExtra("cmd", cmd)
        )
    }

    override fun onResume() {
        super.onResume()
        refreshStatus()
    }

    private fun startAgent() {
        val intent = Intent(this, AgentForegroundService::class.java)
        startForegroundService(intent)
        appendLog("后台服务已启动（BLE + 热点控制）")
        // 引导加入电池优化白名单，提升后台存活
        runCatching {
            startActivity(
                Intent(
                    Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                    Uri.parse("package:$packageName")
                )
            )
        }
        refreshStatus()
    }

    private fun refreshStatus() {
        val on = hotspot.isHotspotOn()
        statusView.text = "热点状态：${if (on) "已开启" else "未开启"}\n共享 SSID：mmmmmm"
    }

    @SuppressLint("InlinedApi")
    private fun requestRuntimePermissions() {
        val wanted = mutableListOf<String>()
        if (checkSelfPermission(android.Manifest.permission.ACCESS_FINE_LOCATION) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            wanted.add(android.Manifest.permission.ACCESS_FINE_LOCATION)
        }
        if (Build.VERSION.SDK_INT >= 31) {
            if (checkSelfPermission(android.Manifest.permission.BLUETOOTH_CONNECT) !=
                PackageManager.PERMISSION_GRANTED
            ) wanted.add(android.Manifest.permission.BLUETOOTH_CONNECT)
            if (checkSelfPermission(android.Manifest.permission.BLUETOOTH_ADVERTISE) !=
                PackageManager.PERMISSION_GRANTED
            ) wanted.add(android.Manifest.permission.BLUETOOTH_ADVERTISE)
        }
        if (wanted.isNotEmpty()) requestPermissions(wanted.toTypedArray(), 1)
    }

    private fun appendLog(msg: String) {
        runOnUiThread {
            logView.append("${timeFmt.format(Date())}  $msg\n")
        }
    }
}
