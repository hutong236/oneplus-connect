package com.hutong.oneplusagent.core

/** Main-thread ownership of the BLE runtime across service and adapter events. */
class BleLifecycle(
    private val start: () -> Boolean,
    private val stop: () -> Unit
) {
    private var running = false

    fun startIfNeeded(): Boolean {
        if (!running) running = start()
        return running
    }

    fun pause() {
        if (!running) return
        running = false
        stop()
    }

    fun shutdown() {
        running = false
        stop()
    }

    fun onStartFailed() = pause()
}
