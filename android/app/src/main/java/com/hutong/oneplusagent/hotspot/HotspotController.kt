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
 * 热点控制策略链，详见 docs/hotspot-strategies.md：
 *   1. 反射 TetheringManager.startTethering（无 Root，本机被 entitlement 拦截，快速失败）
 *   2. Root（su + app_process，Magisk 后可用，本机主路径）
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
    }

    /** 服务端拒绝标志（error=14 entitlement 等），由 TetheringManager 回调置位 */
    @Volatile
    private var serverRejectedTethering = false
    @Volatile
    private var lastTetheringError = -1

    private val executor = Executors.newSingleThreadExecutor()
    private val rootHotspot by lazy { RootHotspot(context) }

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

        serverRejectedTethering = false
        if (tryStartTethering()) {
            if (waitForApState(on = true)) {
                logChain("策略1 startTethering 成功")
                return Result.Success
            }
            logChain(
                if (serverRejectedTethering) "策略1 被服务端拒绝(error=$lastTetheringError)"
                else "策略1 已调用但热点未就绪"
            )
        } else {
            logChain("策略1 startTethering 反射调用失败")
        }

        if (rootHotspot.available()) {
            logChain("策略2 尝试 Root（su + app_process）…")
            if (rootHotspot.enableBlocking() && waitForApState(on = true)) {
                logChain("策略2 Root 成功")
                return Result.Success
            }
            logChain("策略2 Root 执行失败")
        } else {
            logChain("策略2 Root 不可用（未装 Magisk 或未授权 su）")
        }

        // 策略3：兜底拉起设置页
        openTetherSettings()
        return Result.NeedManual("自动开启不可用，已打开热点设置页，请手动开启")
    }

    fun disableBlocking(): Result {
        logChain("disable 开始")
        if (!isHotspotOn()) {
            logChain("热点已关闭，跳过")
            return Result.Success
        }
        if (tryStopTethering() && waitForApState(on = false)) {
            return Result.Success
        }
        if (rootHotspot.available() && rootHotspot.disableBlocking()) {
            return Result.Success
        }
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
        Log.w(TAG, "isWifiApEnabled 反射失败: $t cause=${(t as? java.lang.reflect.InvocationTargetException)?.cause}")
        false
    }

    // ---------- 策略 1：startTethering ----------

    private fun tryStartTethering(): Boolean {
        // Android 11(R) 优先走 TetheringManager：回调是接口，可用动态代理构造
        if (tryTetheringManagerStart()) return true
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
            Log.w(TAG, "startTethering 失败: $t cause=${(t as? java.lang.reflect.InvocationTargetException)?.cause}")
            false
        }
    }

    /** Android 11: TetheringManager.startTethering —— 按运行时实际签名自适应 */
    private fun tryTetheringManagerStart(): Boolean {
        try {
            val tmClass = Class.forName("android.net.TetheringManager")
            val tm = obtainTetheringManager()
            if (tm == null) {
                Log.w(TAG, "tm: 实例获取失败")
                return false
            }
            Log.i(TAG, "tm: 实例获取成功 ${tm.javaClass.name}")

            val method = tmClass.methods.firstOrNull { it.name == "startTethering" }
                ?: run { Log.w(TAG, "tm: 无 startTethering 方法"); return false }
            Log.i(TAG, "tm: 目标签名 (${method.parameterTypes.joinToString { it.name }})")

            val callbackInterface = method.parameterTypes.last()
            val proxy = java.lang.reflect.Proxy.newProxyInstance(
                callbackInterface.classLoader, arrayOf(callbackInterface)
            ) { _, m, args ->
                when (m.name) {
                    "onTetheringStarted" -> Log.i(TAG, "TetheringManager: onTetheringStarted")
                    "onTetheringFailed" -> {
                        val err = (args?.firstOrNull() as? Int) ?: -1
                        serverRejectedTethering = true
                        lastTetheringError = err
                        Log.w(TAG, "TetheringManager: onTetheringFailed error=$err")
                    }
                }
                null
            }

            // 第一个参数：TetheringRequest（顶层或嵌套类，ROM 实现有差异）或 int（旧签名）
            val firstType = method.parameterTypes.firstOrNull()?.name
            val firstArg: Any = when {
                firstType == "int" -> TETHERING_WIFI
                firstType?.endsWith("TetheringRequest") == true -> {
                    val builderClass = Class.forName("$firstType\$Builder")
                    val builder = builderClass
                        .getConstructor(Int::class.javaPrimitiveType)
                        .newInstance(TETHERING_WIFI)
                    // 复刻系统设置页开关热点行为：用户显式指令即视为授权，跳过运营商检查
                    runCatching {
                        builderClass.getMethod("setExemptFromEntitlementCheck", Boolean::class.javaPrimitiveType)
                            .invoke(builder, true)
                    }.onFailure { Log.w(TAG, "tm: setExemptFromEntitlementCheck 不可用: $it") }
                    builderClass.getMethod("build").invoke(builder)
                }
                else -> {
                    Log.w(TAG, "tm: 未知首参类型 $firstType")
                    return false
                }
            }

            // Executor 参数：可能是 java.util.concurrent.Executor
            val params = method.parameterTypes
            val args = arrayOfNulls<Any>(params.size)
            args[0] = firstArg
            for (i in 1 until params.size) {
                args[i] = when {
                    java.util.concurrent.Executor::class.java.isAssignableFrom(params[i]) -> executor
                    else -> proxy
                }
            }
            method.invoke(tm, *args)
            Log.i(TAG, "tm: startTethering 已调用")
            return true
        } catch (t: Throwable) {
            Log.w(TAG, "TetheringManager.startTethering 失败: $t cause=${(t as? java.lang.reflect.InvocationTargetException)?.cause}")
            return false
        }
    }

    /** 枚举本机 TetheringManager 实际可用方法，便于适配不同 ROM */
    private fun dumpTetheringManagerApi() {
        try {
            val tmClass = Class.forName("android.net.TetheringManager")
            val methods = tmClass.declaredMethods.joinToString("; ") { m ->
                "${m.name}(${m.parameterTypes.joinToString { it.simpleName }})"
            }
            Log.i(TAG, "TetheringManager API: $methods")
        } catch (t: Throwable) {
            Log.w(TAG, "dump TetheringManager 失败: $t")
        }
    }

    private fun obtainTetheringManager(): Any? {
        val tmClass = Class.forName("android.net.TetheringManager")
        runCatching { return tmClass.getMethod("getInstance", Context::class.java).invoke(null, context) }
        runCatching { return tmClass.getMethod("getInstance").invoke(null) }
        runCatching {
            val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
            val field = ConnectivityManager::class.java.getDeclaredField("mTetheringManager")
            field.isAccessible = true
            return field.get(cm)
        }
        runCatching { return context.getSystemService("tethering") }
        return null
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
            // 服务端已明确拒绝（如 entitlement error=14），无需继续等待
            if (serverRejectedTethering) return false
            TimeUnit.MILLISECONDS.sleep(AgentConfig.HOTSPOT_POLL_INTERVAL_MS)
        }
        return isHotspotOn() == on
    }

    private fun logChain(msg: String) {
        Log.i(TAG, "[HotspotController] $msg")
    }
}
