package com.hutong.oneplusagent.hotspot

import android.content.Context
import android.util.Log
import java.io.File
import java.util.concurrent.TimeUnit

/**
 * Root 热点策略：经 su 以 root 身份运行 app_process（RootHotspotMain，打包于 assets），
 * 调用 TetheringManager.startTethering —— root 通过 entitlement/MAINLINE_NETWORK_STACK 全部检查。
 * 依赖：Magisk（首次调用会弹授权框，用户允许后记住）。
 */
class RootHotspot(private val context: Context) {

    companion object {
        private const val TAG = "OnePlusAgent"
        private const val JAR_NAME = "root-hotspot.jar"
        private const val MAIN_CLASS = "RootHotspotMain"
        private const val SU_TIMEOUT_S = 30L
    }

    /** su 可用且当前即取得 root（uid=0） */
    fun available(): Boolean = runSu("id")?.contains("uid=0") == true

    fun enableBlocking(): Boolean = run(enable = true)
    fun disableBlocking(): Boolean = run(enable = false)

    private fun run(enable: Boolean): Boolean {
        val jar = ensureJarExtracted() ?: run {
            Log.e(TAG, "assets 中缺少 $JAR_NAME")
            return false
        }
        val mode = if (enable) "enable" else "disable"
        val output = runSu("CLASSPATH=$jar app_process / $MAIN_CLASS $mode")
        Log.i(TAG, "RootHotspot $mode 输出:\n$output")
        return output?.contains(if (enable) "已开启" else "已关闭") == true
    }

    private fun ensureJarExtracted(): String? = try {
        val f = File(context.filesDir, JAR_NAME)
        if (!f.exists() || f.length() == 0L) {
            context.assets.open(JAR_NAME).use { input ->
                f.outputStream().use { input.copyTo(it) }
            }
        }
        f.absolutePath
    } catch (t: Throwable) {
        Log.w(TAG, "解压 $JAR_NAME 失败: $t")
        null
    }

    private fun runSu(cmd: String): String? {
        return try {
            val proc = ProcessBuilder("su", "-c", cmd)
                .redirectErrorStream(true)
                .start()
            if (!proc.waitFor(SU_TIMEOUT_S, TimeUnit.SECONDS)) {
                proc.destroyForcibly()
                Log.w(TAG, "su 命令超时: $cmd")
                return null
            }
            proc.inputStream.bufferedReader().readText()
        } catch (t: Throwable) {
            Log.w(TAG, "su 不可用: $t")
            null
        }
    }
}
