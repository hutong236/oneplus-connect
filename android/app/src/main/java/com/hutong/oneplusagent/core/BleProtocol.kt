package com.hutong.oneplusagent.core

import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.security.MessageDigest
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec
import java.util.UUID

/**
 * BLE 协议 v2，契约见 docs/ble-protocol.md。
 * 修改本文件必须同步 macOS 端 Protocol.swift。
 */
object BleProtocol {
    const val VERSION = 2

    val SERVICE_UUID: UUID = UUID.fromString("7b6e0001-2a4c-4e6d-9b8a-5f1e3d5c7a9b")
    val CMD_UUID: UUID = UUID.fromString("7b6e0002-2a4c-4e6d-9b8a-5f1e3d5c7a9b")
    val STATUS_UUID: UUID = UUID.fromString("7b6e0003-2a4c-4e6d-9b8a-5f1e3d5c7a9b")

    const val CMD_PING = 0x01
    const val CMD_CONNECT = 0x10
    const val CMD_DISCONNECT = 0x11
    const val CMD_GET_STATUS = 0x20

    const val FLAG_HOTSPOT_ON = 0x01
    const val FLAG_UPSTREAM_OK = 0x02
    const val FLAG_CMD_FAILED = 0x04

    const val CMD_FRAME_SIZE = 26
    const val BATTERY_UNKNOWN = 0xFF

    data class Command(val cmd: Int, val nonce: Long)

    data class Status(
        val hotspotOn: Boolean,
        val upstreamOk: Boolean,
        val cmdFailed: Boolean,
        val batteryPercent: Int,
        val ssid: String
    )

    fun auth(secret: String, nonce: Long, cmd: Int): ByteArray {
        val mac = Mac.getInstance("HmacSHA256")
        mac.init(SecretKeySpec(secret.toByteArray(Charsets.UTF_8), "HmacSHA256"))
        mac.update(ByteBuffer.allocate(8).order(ByteOrder.LITTLE_ENDIAN).putLong(nonce).array())
        mac.update(byteArrayOf(cmd.toByte()))
        return mac.doFinal().copyOfRange(0, 16)
    }

    /** 解析并校验 CMD 帧；长度/版本/鉴权任一不符返回 null */
    fun parseCommand(bytes: ByteArray, secret: String): Command? {
        if (bytes.size != CMD_FRAME_SIZE) return null
        if (bytes[0].toInt() and 0xFF != VERSION) return null
        if (secret.toByteArray(Charsets.UTF_8).size < 32) return null
        val cmd = bytes[1].toInt() and 0xFF
        val nonce = ByteBuffer.wrap(bytes, 2, 8).order(ByteOrder.LITTLE_ENDIAN).long
        val expected = auth(secret, nonce, cmd)
        val received = bytes.copyOfRange(10, CMD_FRAME_SIZE)
        return if (MessageDigest.isEqual(expected, received)) Command(cmd, nonce) else null
    }

    fun isFreshNonce(nonce: Long, nowMillis: Long, lastAcceptedMillis: Long): Boolean {
        val timestampMillis = nonce ushr 16
        return timestampMillis > lastAcceptedMillis &&
            timestampMillis <= nowMillis + 30_000L &&
            timestampMillis >= nowMillis - 300_000L
    }

    fun encodeStatus(s: Status): ByteArray {
        var flags = 0
        if (s.hotspotOn) flags = flags or FLAG_HOTSPOT_ON
        if (s.upstreamOk) flags = flags or FLAG_UPSTREAM_OK
        if (s.cmdFailed) flags = flags or FLAG_CMD_FAILED

        var ssidBytes = s.ssid.toByteArray(Charsets.UTF_8)
        if (ssidBytes.size > 20) ssidBytes = ssidBytes.copyOf(20) // 单帧保护，足够容纳 mmmmmm

        val out = ByteArray(4 + ssidBytes.size)
        out[0] = VERSION.toByte()
        out[1] = flags.toByte()
        out[2] = if (s.batteryPercent == BATTERY_UNKNOWN) BATTERY_UNKNOWN.toByte()
        else s.batteryPercent.coerceIn(0, 100).toByte()
        out[3] = ssidBytes.size.toByte()
        System.arraycopy(ssidBytes, 0, out, 4, ssidBytes.size)
        return out
    }
}
