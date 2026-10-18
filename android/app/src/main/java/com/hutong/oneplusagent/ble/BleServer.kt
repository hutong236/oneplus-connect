package com.hutong.oneplusagent.ble

import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattDescriptor
import android.bluetooth.BluetoothGattServer
import android.bluetooth.BluetoothGattServerCallback
import android.bluetooth.BluetoothGattService
import android.bluetooth.BluetoothManager
import android.bluetooth.le.AdvertiseCallback
import android.bluetooth.le.AdvertiseData
import android.bluetooth.le.AdvertiseSettings
import android.content.Context
import android.os.ParcelUuid
import android.util.Log
import com.hutong.oneplusagent.core.AgentConfig
import com.hutong.oneplusagent.core.BleProtocol
import java.util.UUID
import java.util.concurrent.CopyOnWriteArraySet

/**
 * BLE 外设：GATT Server + 广播。
 * 回调发生在 Binder 线程，Listener 实现方需自行切换线程。
 */
class BleServer(
    context: Context,
    private val listener: Listener
) {
    interface Listener {
        /** 收到通过鉴权的指令；返回后由服务端回 ACK */
        fun onCommand(cmd: Int)
        fun onClientConnected(connected: Boolean)
    }

    companion object {
        private const val TAG = "OnePlusAgent"
        private val CCCD_UUID: UUID = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")
    }

    private val appContext = context.applicationContext
    private val bluetoothManager =
        appContext.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
    private var gattServer: BluetoothGattServer? = null
    private var service: BluetoothGattService? = null
    private var advertising = false

    @Volatile
    private var statusBytes: ByteArray = BleProtocol.encodeStatus(
        BleProtocol.Status(false, false, false, BleProtocol.BATTERY_UNKNOWN, AgentConfig.HOTSPOT_SSID)
    )

    private val connectedDevices = CopyOnWriteArraySet<BluetoothDevice>()

    private val advertiseCallback = object : AdvertiseCallback() {
        override fun onStartSuccess(settingsInEffect: AdvertiseSettings?) {
            Log.i(TAG, "BLE 广播已开启")
        }

        override fun onStartFailure(errorCode: Int) {
            Log.e(TAG, "BLE 广播失败 errorCode=$errorCode")
        }
    }

    /** 蓝牙已开启返回 true 并开始广播；蓝牙关闭返回 false */
    fun start(): Boolean {
        val adapter: BluetoothAdapter = bluetoothManager.adapter ?: return false
        if (!adapter.isEnabled) {
            Log.w(TAG, "蓝牙未开启，无法启动 BLE")
            return false
        }
        val advertiser = adapter.bluetoothLeAdvertiser ?: run {
            Log.e(TAG, "设备不支持 BLE 广播")
            return false
        }

        stop()

        val server = bluetoothManager.openGattServer(appContext, gattCallback)
            ?: run { Log.e(TAG, "openGattServer 失败"); return false }
        gattServer = server

        val svc = buildService()
        service = svc
        server.addService(svc)

        val settings = AdvertiseSettings.Builder()
            .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY)
            .setConnectable(true)
            .build()
        val data = AdvertiseData.Builder()
            .setIncludeDeviceName(false)
            .addServiceUuid(ParcelUuid(BleProtocol.SERVICE_UUID))
            .build()
        val scanResponse = AdvertiseData.Builder()
            .setIncludeDeviceName(true)
            .build()
        advertiser.startAdvertising(settings, data, scanResponse, advertiseCallback)
        advertising = true
        return true
    }

    fun stop() {
        if (advertising) {
            try {
                bluetoothManager.adapter?.bluetoothLeAdvertiser?.stopAdvertising(advertiseCallback)
            } catch (t: Throwable) {
                Log.w(TAG, "stopAdvertising: $t")
            }
            advertising = false
        }
        gattServer?.close()
        gattServer = null
        connectedDevices.clear()
    }

    /** 状态变化时推送给所有已订阅的客户端 */
    fun updateStatus(status: BleProtocol.Status) {
        statusBytes = BleProtocol.encodeStatus(status)
        val server = gattServer ?: return
        val svc = service ?: return
        for (device in connectedDevices) {
            val ch = svc.getCharacteristic(BleProtocol.STATUS_UUID) ?: continue
            @Suppress("DEPRECATION")
            ch.value = statusBytes
            @Suppress("DEPRECATION")
            server.notifyCharacteristicChanged(device, ch, false)
        }
    }

    private fun buildService(): BluetoothGattService =
        BluetoothGattService(BleProtocol.SERVICE_UUID, BluetoothGattService.SERVICE_TYPE_PRIMARY).apply {
            addCharacteristic(
                BluetoothGattCharacteristic(
                    BleProtocol.CMD_UUID,
                    BluetoothGattCharacteristic.PROPERTY_WRITE,
                    BluetoothGattCharacteristic.PERMISSION_WRITE
                )
            )
            addCharacteristic(
                BluetoothGattCharacteristic(
                    BleProtocol.STATUS_UUID,
                    BluetoothGattCharacteristic.PROPERTY_READ or BluetoothGattCharacteristic.PROPERTY_NOTIFY,
                    BluetoothGattCharacteristic.PERMISSION_READ
                ).apply {
                    addDescriptor(
                        @Suppress("DEPRECATION")
                        BluetoothGattDescriptor(
                            CCCD_UUID,
                            BluetoothGattDescriptor.PERMISSION_WRITE
                        )
                    )
                }
            )
        }

    private val gattCallback = object : BluetoothGattServerCallback() {

        override fun onConnectionStateChange(device: BluetoothDevice, status: Int, newState: Int) {
            Log.i(TAG, "BLE 连接状态 device=${device.address} state=$newState status=$status")
            if (newState == android.bluetooth.BluetoothProfile.STATE_CONNECTED) {
                connectedDevices.add(device)
                listener.onClientConnected(true)
            } else {
                connectedDevices.remove(device)
                listener.onClientConnected(connectedDevices.isNotEmpty())
            }
        }

        override fun onCharacteristicWriteRequest(
            device: BluetoothDevice,
            requestId: Int,
            characteristic: BluetoothGattCharacteristic,
            preparedWrite: Boolean,
            responseNeeded: Boolean,
            offset: Int,
            value: ByteArray?
        ) {
            if (characteristic.uuid != BleProtocol.CMD_UUID) return
            val bytes = value ?: ByteArray(0)
            val command = BleProtocol.parseCommand(bytes, AgentConfig.SHARED_SECRET)
            if (command == null) {
                Log.w(TAG, "CMD 帧无效（长度=${bytes.size} 或鉴权失败），已忽略")
                if (responseNeeded) {
                    gattServer?.sendResponse(device, requestId, android.bluetooth.BluetoothGatt.GATT_FAILURE, 0, null)
                }
                return
            }
            Log.i(TAG, "收到指令 cmd=0x%02x nonce=0x%08x".format(command.cmd, command.nonce))
            if (responseNeeded) {
                gattServer?.sendResponse(device, requestId, android.bluetooth.BluetoothGatt.GATT_SUCCESS, 0, null)
            }
            listener.onCommand(command.cmd)
        }

        override fun onCharacteristicReadRequest(
            device: BluetoothDevice,
            requestId: Int,
            offset: Int,
            characteristic: BluetoothGattCharacteristic
        ) {
            if (characteristic.uuid == BleProtocol.STATUS_UUID) {
                gattServer?.sendResponse(
                    device, requestId, android.bluetooth.BluetoothGatt.GATT_SUCCESS, offset,
                    if (offset == 0) statusBytes else null
                )
            }
        }

        override fun onDescriptorWriteRequest(
            device: BluetoothDevice,
            requestId: Int,
            descriptor: BluetoothGattDescriptor,
            preparedWrite: Boolean,
            responseNeeded: Boolean,
            offset: Int,
            value: ByteArray?
        ) {
            // CCCD 订阅成功后立即推一帧当前状态，Mac 无需额外 GET_STATUS
            if (descriptor.uuid == CCCD_UUID) {
                if (responseNeeded) {
                    gattServer?.sendResponse(
                        device, requestId, android.bluetooth.BluetoothGatt.GATT_SUCCESS, 0, null
                    )
                }
                val ch = service?.getCharacteristic(BleProtocol.STATUS_UUID)
                if (ch != null && value != null && value.isNotEmpty() && value[0].toInt() != 0) {
                    @Suppress("DEPRECATION")
                    ch.value = statusBytes
                    @Suppress("DEPRECATION")
                    gattServer?.notifyCharacteristicChanged(device, ch, false)
                }
            }
        }
    }
}
