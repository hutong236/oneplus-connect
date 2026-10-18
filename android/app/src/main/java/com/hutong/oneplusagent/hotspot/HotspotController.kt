package com.hutong.oneplusagent.hotspot

import android.content.Context
import android.content.Intent
import android.net.ConnectivityManager
import android.net.wifi.WifiManager
import android.util.Log
import com.hutong.oneplusagent.core.AgentConfig
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/**
 * 热点控制策略链（无 Root 优先），详见 docs/hotspot-strategies.md：
 *   1. 反射 ConnectivityManager.startTethering(TETHERING_WIFI)
 *   2. Root 通道（当前设备未 Root，预留）
 *   3. 拉起系统热点设置页（需手动一次点击）
 */
class HotspotController(private val context: Context) {

    sealed class Result {
        object Success : Result()
        data class Failure(val reason: String) : Result()
        /** 已拉起设置页，等待用户手动开启 */
        data class NeedManual(val reason: String) : Result()
    }

    companion object {
        private const val TAG = "OnePlusAgent"
        private const val TETHERING_WIFI = 0
        private const val AP_STATE_ACTION = "android.net.wifi.WIFI_AP_STATE_CHANGED"
    }

    private val executor = Executors.newSingleThreadExecutor()

    /** 异步入口，回调在调用线程不保证；UI 侧自行 post */
    fun enable(onResult: (Result) -> Unit) {
        executor.execute { onResult(enableBlocking()) }
    }

    fun disable(onResult: (Result) -> Unit) {
        executor.execute { onResult(disableBlocking()) }
    }

    fun shutdown() {
        executor.shutdownNow()
    }

    fun enableBlocking(): Result {
        logChain("enable 开始")
        if (isHotspotOn()) {
            logChain("热点已开启，跳过")
            return Result.Success
        }

        if (tryStartTethering()) {
            if (waitForApState(on = true)) {
                logChain("策略1 startTethering 成功")
                return Result.Success
            }
            logChain("策略1 已调用但热点未就绪")
        } else {
            logChain("策略1 startTethering 反射调用失败")
        }

        if (tryRootEnable()) {
            if (waitForApState(on = true)) {
                logChain("策略2 Root 通道成功")
                return Result.Success
            }
        }

        // 策略3：兜底拉起设置页
        openTetherSettings()
        return Result.NeedManual("反射与 Root 均不可用，已打开热点设置页，请手动开启")
    }

    fun disableBlocking(): Result {
        logChain("disable 开始")
        if (!isHotspotOn()) {
            logChain("热点已关闭，跳过")
            return Result.Success
        }
        if (tryStopTethering()) {
            if (waitForApState(on = false)) return Result.Success
        }
        tryRootDisable()
        if (!isHotspotOn()) return Result.Success
        openTetherSettings()
        return Result.NeedManual("无法自动关闭，已打开热点设置页")
    }

    /** WifiManager.isWifiApEnabled（隐藏 API，反射） */
    fun isHotspotOn(): Boolean = try {
        val wifi = context.applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
        val method = WifiManager::class.java.getMethod("isWifiApEnabled")
        method.invoke(wifi) as Boolean
    } catch (t: Throwable) {
        Log.w(TAG, "isWifiApEnabled 反射失败: $t")
        false
    }

    // ---------- 策略 1：startTethering ----------

    private fun tryStartTethering(): Boolean {
        return try {
            val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
            val callbackClass = Class.forName("android.net.ConnectivityManager\$OnStartTetheringCallback")
            // 尝试 4 参签名（type, showProvisioningUi, callback, handler），再退 3 参
            val invoked = runCatching {
                val m = ConnectivityManager::class.java.getMethod(
                    "startTethering",
                    Int::class.javaPrimitiveType,
                    Boolean::class.javaPrimitiveType,
                    callbackClass,
                    android.os.Handler::class.java
                )
                m.invoke(cm, TETHERING_WIFI, false, null, null)
                true
            }.getOrElse {
                val m = ConnectivityManager::class.java.getMethod(
                    "startTethering",
                    Int::class.javaPrimitiveType,
                    Boolean::class.javaPrimitiveType,
                    callbackClass
                )
                m.invoke(cm, TETHERING_WIFI, false, null)
                true
            }
            Log.i(TAG, "startTethering 已调用 invoked=$invoked")
            true
        } catch (t: Throwable) {
            Log.w(TAG, "startTethering 失败: $t")
            false
        }
    }

    private fun tryStopTethering(): Boolean = try {
        val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val m = ConnectivityManager::class.java.getMethod(
            "stopTethering", Int::class.javaPrimitiveType
        )
        m.invoke(cm, TETHERING_WIFI)
        true
    } catch (t: Throwable) {
        Log.w(TAG, "stopTethering 失败: $t")
        false
    }

    // ---------- 策略 2：Root（预留） ----------

    private fun hasSu(): Boolean = try {
        ProcessBuilder("which", "su").start().inputStream.readBytes().isNotEmpty()
    } catch (t: Throwable) {
        false
    }

    private fun tryRootEnable(): Boolean {
        if (!hasSu()) return false
        // 不同 ROM 命令有差异，Android 11 常见为 cmd wifi start-softap
        val cmds = listOf("cmd wifi start-softap ap0", "svc wifi enable && cmd wifi start-softap ap0")
        for (cmd in cmds) {
            if (runSu(cmd)) return true
        }
        return false
    }

    private fun tryRootDisable(): Boolean {
        if (!hasSu()) return false
        return runSu("cmd wifi stop-softap")
    }

    private fun runSu(cmd: String): Boolean = try {
        val p = ProcessBuilder("su", "-c", cmd).start()
        p.waitFor() == 0
    } catch (t: Throwable) {
        Log.w(TAG, "su 执行失败 [$cmd]: $t")
        false
    }

    // ---------- 策略 3：设置页兜底 ----------

    private fun openTetherSettings() {
        try {
            context.startActivity(
                Intent("android.settings.TETHER_SETTINGS")
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            )
        } catch (t: Throwable) {
            Log.w(TAG, "打开热点设置失败: $t")
        }
    }

    // ---------- 轮询确认 ----------

    private fun waitForApState(on: Boolean): Boolean {
        val deadline = System.currentTimeMillis() + AgentConfig.HOTSPOT_POLL_TIMEOUT_MS
        while (System.currentTimeMillis() < deadline) {
            if (isHotspotOn() == on) return true
            TimeUnit.MILLISECONDS.sleep(AgentConfig.HOTSPOT_POLL_INTERVAL_MS)
        }
        return isHotspotOn() == on
    }

    private fun logChain(msg: String) {
        Log.i(TAG, "[HotspotController] $msg")
    }
}
