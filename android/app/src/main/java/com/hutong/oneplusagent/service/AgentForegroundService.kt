package com.hutong.oneplusagent.service

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.bluetooth.BluetoothAdapter
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ServiceInfo
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.BatteryManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.Log
import com.hutong.oneplusagent.MainActivity
import com.hutong.oneplusagent.ble.BleServer
import com.hutong.oneplusagent.core.BleProtocol
import com.hutong.oneplusagent.core.BleLifecycle
import com.hutong.oneplusagent.hotspot.HotspotController
import java.util.concurrent.Executors

/**
 * 常驻前台服务：持有 BLE GATT Server 与广播，接收 Mac 指令并控制热点。
 */
class AgentForegroundService : Service(), BleServer.Listener {

    companion object {
        private const val TAG = "OnePlusAgent"
        private const val CHANNEL_ID = "oneplus_agent"
        private const val NOTIF_ID = 1
        private const val AP_STATE_ACTION = "android.net.wifi.WIFI_AP_STATE_CHANGED"
    }

    private val main = Handler(Looper.getMainLooper())
    private val executor = Executors.newSingleThreadExecutor()
    private lateinit var ble: BleServer
    private lateinit var bleLifecycle: BleLifecycle
    private lateinit var hotspot: HotspotController

    @Volatile
    private var cmdFailed = false

    private val systemStateReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            when (intent?.action) {
                AP_STATE_ACTION -> pushStatus()
                BluetoothAdapter.ACTION_STATE_CHANGED -> when (
                    intent.getIntExtra(BluetoothAdapter.EXTRA_STATE, BluetoothAdapter.ERROR)
                ) {
                    BluetoothAdapter.STATE_ON -> {
                        val ok = bleLifecycle.startIfNeeded()
                        updateNotification(if (ok) "BLE 广播已恢复，等待 Mac 连接" else "BLE 广播恢复失败，请重试")
                        Log.i(TAG, "蓝牙开启，恢复 BLE ble=$ok")
                        if (ok) pushStatus()
                    }
                    BluetoothAdapter.STATE_TURNING_OFF, BluetoothAdapter.STATE_OFF -> {
                        bleLifecycle.pause()
                        updateNotification("蓝牙已关闭，开启后自动恢复")
                        Log.i(TAG, "蓝牙关闭，暂停 BLE")
                    }
                }
            }
        }
    }

    override fun onCreate() {
        super.onCreate()
        hotspot = HotspotController(this)
        ble = BleServer(this, this)
        bleLifecycle = BleLifecycle(start = { ble.start() }, stop = { ble.stop() })
        registerReceiver(systemStateReceiver, IntentFilter(AP_STATE_ACTION).apply {
            addAction(BluetoothAdapter.ACTION_STATE_CHANGED)
        })
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startInForeground()
        val ok = bleLifecycle.startIfNeeded()
        updateNotification(if (ok) "BLE 广播中，等待 Mac 连接" else "蓝牙未开启，请打开蓝牙后重试")
        Log.i(TAG, "服务启动 ble=$ok")
        return START_STICKY
    }

    override fun onDestroy() {
        unregisterReceiver(systemStateReceiver)
        bleLifecycle.shutdown()
        hotspot.shutdown()
        executor.shutdownNow()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    // ---------- BleServer.Listener（Binder 线程回调） ----------

    override fun onCommand(cmd: Int) {
        main.post { handleCommand(cmd) }
    }

    override fun onClientConnected(connected: Boolean) {
        Log.i(TAG, "Mac 连接状态: $connected")
    }

    override fun onAdvertisingFailed(errorCode: Int) {
        bleLifecycle.onStartFailed()
        updateNotification("BLE 广播失败（$errorCode），请重新启动后台服务")
    }

    private fun handleCommand(cmd: Int) {
        when (cmd) {
            BleProtocol.CMD_PING, BleProtocol.CMD_GET_STATUS -> {
                cmdFailed = false
                pushStatus()
            }
            BleProtocol.CMD_CONNECT -> executor.execute {
                val result = hotspot.enableBlocking()
                main.post {
                    cmdFailed = result !is HotspotController.Result.Success
                    pushStatus()
                }
            }
            BleProtocol.CMD_DISCONNECT -> executor.execute {
                val result = hotspot.disableBlocking()
                main.post {
                    cmdFailed = result !is HotspotController.Result.Success
                    pushStatus()
                }
            }
            else -> Log.w(TAG, "未知指令 0x%02x".format(cmd))
        }
    }

    // ---------- 状态推送 ----------

    private fun pushStatus() {
        ble.updateStatus(
            BleProtocol.Status(
                hotspotOn = hotspot.isHotspotOn(),
                upstreamOk = upstreamOk(),
                cmdFailed = cmdFailed,
                batteryPercent = batteryPercent(),
                ssid = com.hutong.oneplusagent.core.AgentConfig.HOTSPOT_SSID
            )
        )
    }

    private fun upstreamOk(): Boolean = try {
        val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val caps = cm.getNetworkCapabilities(cm.activeNetwork) ?: return false
        caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) &&
            caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED)
    } catch (t: Throwable) {
        false
    }

    private fun batteryPercent(): Int = try {
        val intent = registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        val level = intent?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
        val scale = intent?.getIntExtra(BatteryManager.EXTRA_SCALE, -1) ?: -1
        if (level >= 0 && scale > 0) level * 100 / scale else BleProtocol.BATTERY_UNKNOWN
    } catch (t: Throwable) {
        BleProtocol.BATTERY_UNKNOWN
    }

    // ---------- 通知 ----------

    private fun startInForeground() {
        val nm = getSystemService(NotificationManager::class.java)
        if (nm.getNotificationChannel(CHANNEL_ID) == null) {
            nm.createNotificationChannel(
                NotificationChannel(CHANNEL_ID, "OnePlus Agent", NotificationManager.IMPORTANCE_LOW)
            )
        }
        if (Build.VERSION.SDK_INT >= 29) {
            startForeground(NOTIF_ID, buildNotification("启动中…"), ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE)
        } else {
            startForeground(NOTIF_ID, buildNotification("启动中…"))
        }
    }

    private fun updateNotification(text: String) {
        val nm = getSystemService(NotificationManager::class.java)
        nm.notify(NOTIF_ID, buildNotification(text))
    }

    private fun buildNotification(text: String): Notification {
        val contentIntent = PendingIntent.getActivity(
            this, 0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        return Notification.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.stat_sys_data_bluetooth)
            .setContentTitle("OnePlus Agent")
            .setContentText(text)
            .setContentIntent(contentIntent)
            .setOngoing(true)
            .build()
    }
}
