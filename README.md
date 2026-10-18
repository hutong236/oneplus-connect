# OnePlus Connect

让 Mac 通过 **蓝牙 BLE** 一键唤醒 OnePlus 6T（Android 11）的共享热点并自动联网，全程不依赖 USB 数据线。

```
Mac 菜单栏点击「一键连接」
        ↓  BLE 写入 CONNECT 指令
OnePlus 6T Agent(前台服务) 自动开启热点 mmmmmm
        ↓  BLE 回传状态(hotspot on)
Mac 自动加入 Wi-Fi mmmmmm → 验证连通性 → 完成
```

## 仓库结构

```
my-Android-wlan/
├── android/    OnePlus Agent —— Kotlin 安卓端：BLE 外设 + 热点控制 + 前台服务
├── macos/      OnePlus Connect —— SwiftUI 菜单栏应用：BLE 中心设备 + 自动入网
├── docs/       架构设计、BLE 协议、热点控制策略
└── openspec/   OpenSpec 规范工作流（提案/变更管理）
```

## 快速开始

### macOS 端（OnePlus Connect）

依赖：Xcode 26+（Swift 5.10+）

```bash
cd macos
swift build && swift run
```

首次使用前编辑 `macos/Sources/OnePlusConnect/Config.swift`，填入 Wi-Fi 密码与配对密钥（需与 Android 端一致）。

### Android 端（OnePlus Agent）

依赖：JDK 17+、Android SDK（Platform 34）。本机尚未安装 SDK/Gradle，可任选其一：

```bash
# 方式一：安装 Android Studio（图形界面，推荐日常开发）
# 方式二：命令行工具
brew install --cask android-commandlinetools
sdkmanager "platforms;android-34" "build-tools;34.0.0" "platform-tools"
```

然后：

```bash
cd android
./gradlew assembleDebug          # 已内置 Gradle Wrapper
adb install app/build/outputs/apk/debug/app-debug.apk
```

安装后打开 App → 授权 → 启动后台服务，保持蓝牙开启。

## 优先级路线

| 优先级 | 工作 | 验收标准 | 状态 |
|---|---|---|---|
| P0 | BLE 通信 | Mac 能发现 OnePlus 6T 并发送指令 | 🔨 开发中 |
| P0 | 热点自动控制 | 手机收到指令后自动开启共享热点 | 🔨 开发中（先验证无 Root 方案） |
| P0 | Mac 自动联网 | 自动加入 mmmmmm 并验证连通 | 🔨 开发中 |
| P1 | 锁屏运行 / 自动重连 / 菜单栏管理 | — | ⏳ |
| P2 | Clash(TUN) 兼容 | 开关 TUN 时连接/断开正常 | ⏳ |

详细设计见 [docs/architecture.md](docs/architecture.md)、[docs/ble-protocol.md](docs/ble-protocol.md)、[docs/hotspot-strategies.md](docs/hotspot-strategies.md)。

## 当前环境事实（2026-10 检测）

- Mac：en0 = 192.168.105.154，已接入 mmmmmm，默认网关 192.168.105.34
- OnePlus 6T：wlan0 = 192.168.105.34（网关即手机），rmnet_data2 为移动数据出口
- 手机未 Root、Bootloader 锁定；目标设备 Android 11（API 30）
