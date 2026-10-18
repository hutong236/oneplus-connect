# OnePlus Agent（Android 端）

Kotlin 安卓应用：BLE GATT 服务端 + 热点控制策略链 + 前台服务。目标设备 OnePlus 6T（A6010，Android 11）。

## 构建

```bash
# 前置：JDK 17+（本机 JDK 23 可用）、Android SDK Platform 34
./gradlew assembleDebug
adb install app/build/outputs/apk/debug/app-debug.apk
```

## 使用

1. 打开 App，授予定位/蓝牙权限（引导加入电池优化白名单）。
2. 点「启动后台服务」——通知栏出现常驻服务，BLE 开始广播。
3. 可先点「测试：开启热点」单独验证策略链（重点观察 logcat）。

```bash
adb logcat -s OnePlusAgent     # 观察策略链与 BLE 日志
```

## 结构

```
app/src/main/java/com/hutong/oneplusagent/
├── MainActivity.kt              # 测试入口 UI
├── BootReceiver.kt              # 开机自启
├── core/
│   ├── AgentConfig.kt           # 共享密钥 / SSID / 轮询参数
│   └── BleProtocol.kt           # 协议编解码（与 macos 端 Protocol.swift 对应）
├── ble/
│   └── BleServer.kt             # GATT Server + 广播 + 状态推送
├── hotspot/
│   └── HotspotController.kt     # 策略链：startTethering 反射 → Root → 设置页
└── service/
    └── AgentForegroundService.kt# 前台服务：指令分发 / 状态聚合
```

零第三方依赖（不引入 AndroidX），降低无 SDK 环境的构建变量。
