package com.hutong.oneplusagent.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class BleProtocolTest {
    @Test
    fun parsesValidV2HmacFrame() {
        val nonce = 0x0102030405060708L
        val key = "a".repeat(32)
        assertEquals(
            listOf(0xd4, 0xe6, 0x88, 0x00, 0xb9, 0x4a, 0x40, 0x16, 0x43, 0xdf, 0x56, 0xa8, 0xa1, 0x6d, 0xbc, 0xb0),
            BleProtocol.auth(key, nonce, BleProtocol.CMD_CONNECT).map { it.toInt() and 0xff }
        )
        val frame = byteArrayOf(2, BleProtocol.CMD_CONNECT.toByte()) +
            java.nio.ByteBuffer.allocate(8).order(java.nio.ByteOrder.LITTLE_ENDIAN).putLong(1_800_000_000_123L shl 16).array() +
            BleProtocol.auth("a".repeat(32), 1_800_000_000_123L shl 16, BleProtocol.CMD_CONNECT)

        val parsed = BleProtocol.parseCommand(frame, "a".repeat(32))

        assertEquals(BleProtocol.CMD_CONNECT, parsed?.cmd)
        assertNull(BleProtocol.parseCommand(frame.copyOf().apply { this[lastIndex] = (this[lastIndex].toInt() xor 1).toByte() }, "a".repeat(32)))
    }

    @Test
    fun statusPreservesUnknownBattery() {
        val decoded = BleProtocol.encodeStatus(BleProtocol.Status(false, false, false, BleProtocol.BATTERY_UNKNOWN, "mmmmmm"))
        assertEquals(BleProtocol.BATTERY_UNKNOWN.toByte(), decoded[2])
    }

    @Test
    fun rejectsReplayedStaleAndFutureNonces() {
        val now = 1_800_000_000_000L
        val current = now shl 16

        assertEquals(true, BleProtocol.isFreshNonce(current or 1, now, now - 1))
        assertEquals(false, BleProtocol.isFreshNonce(current or 2, now, now))
        assertEquals(false, BleProtocol.isFreshNonce((now - 300_001) shl 16, now, 0))
        assertEquals(false, BleProtocol.isFreshNonce((now + 30_001) shl 16, now, 0))
    }
}
