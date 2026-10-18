package com.hutong.oneplusagent.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class BleLifecycleTest {
    @Test
    fun repeatedServiceStartKeepsExistingConnection() {
        var starts = 0
        val lifecycle = BleLifecycle(start = { starts++; true }, stop = {})
        assertTrue(lifecycle.startIfNeeded())
        assertTrue(lifecycle.startIfNeeded())
        assertEquals(1, starts)
    }

    @Test
    fun bluetoothOffThenOnRestartsRuntime() {
        var starts = 0
        var stops = 0
        val lifecycle = BleLifecycle(start = { starts++; true }, stop = { stops++ })
        lifecycle.startIfNeeded()
        lifecycle.pause()
        lifecycle.pause()
        assertEquals(1, stops)
        assertTrue(lifecycle.startIfNeeded())
        assertEquals(2, starts)
    }

    @Test
    fun initiallyDisabledBluetoothCanRecoverWithoutRestartingService() {
        var bluetoothOn = false
        val lifecycle = BleLifecycle(start = { bluetoothOn }, stop = {})
        assertFalse(lifecycle.startIfNeeded())
        bluetoothOn = true
        assertTrue(lifecycle.startIfNeeded())
    }

    @Test
    fun shutdownClosesRuntimeAndAllowsFreshStart() {
        var stops = 0
        var starts = 0
        val lifecycle = BleLifecycle(start = { starts++; true }, stop = { stops++ })
        lifecycle.startIfNeeded()
        lifecycle.shutdown()
        assertEquals(1, stops)
        assertTrue(lifecycle.startIfNeeded())
        assertEquals(2, starts)
    }

    @Test
    fun asynchronousAdvertisingFailureAllowsServiceStartToRetry() {
        var starts = 0
        var stops = 0
        val lifecycle = BleLifecycle(start = { starts++; true }, stop = { stops++ })
        lifecycle.startIfNeeded()
        lifecycle.onStartFailed()
        assertEquals(1, stops)
        assertTrue(lifecycle.startIfNeeded())
        assertEquals(2, starts)
    }
}
