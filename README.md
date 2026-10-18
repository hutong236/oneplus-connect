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
oneplus-connect/
├── android/    OnePlus Agent —— Kotlin 安卓端：BLE 外设 + 热点控制 + 前台服务
├── macos/      OnePlus Connect —— SwiftUI 菜单栏应用：BLE 中心设备 + 自动入网
├── docs/       架构设计、BLE 协议、热点控制策略
└── openspec/   OpenSpec 规范工作流（提案/变更管理）
```

## 快速开始

### macOS 端（OnePlus Connect）

依赖：Xcode 26+（Swift 5.10+）

```bash
bash script/build_and_run.sh
```

首次使用前按 [真机验收清单](docs/real-device-acceptance.md) 配置 BLE 配对密钥：Android 应用通过 Android Keystore 加密保存，macOS 从 Keychain 读取。不要把密钥写入源码或提交到 Git。

### Android 端（OnePlus Agent）

依赖：JDK 17+、Android SDK（Platform 34）。尚未安装 SDK 时，可任选其一：

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
| P0 | BLE 通信 | Mac 能发现 OnePlus 6T 并发送指令 | 已实机连接；完整验收见清单 |
| P0 | 热点自动控制 | 手机收到指令后自动开启共享热点 | Root 开启/关闭已由实机日志确认 |
| P0 | Mac 自动联网 | 自动加入 mmmmmm 并验证连通 | 热点链路已实机验证；互联网探测误判修复后待复测 |
| P1 | 锁屏运行 / 自动重连 / 菜单栏管理 | 后台服务、重连开关、蓝牙恢复及断开行为 | 手机蓝牙恢复已实机验证；其余计划测试用户确认完成 |
| P2 | Clash(TUN) 兼容 | 开关 TUN 时连接/断开正常 | 用户确认可上网；互联网探测改为遵循当前系统路由，待复测状态显示 |

详细设计见 [docs/architecture.md](docs/architecture.md)、[docs/ble-protocol.md](docs/ble-protocol.md)、[docs/hotspot-strategies.md](docs/hotspot-strategies.md)。

## 当前环境事实（2026-10-19）

- OnePlus 6T 运行 Android 11（API 30）；应用的 Root 热点控制路径已成功执行开启和关闭，不能再按“未 Root”描述。
- Mac 的热点连接使用 en0，手机热点使用 wlan0；IP 与网关由 DHCP 动态分配，不作为固定配置。
- 手机 Agent 前台服务和电池优化白名单已确认。完整真机结果以 [验收清单](docs/real-device-acceptance.md) 为准，单元测试不代表真机通过。
