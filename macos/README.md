# OnePlus Connect（macOS 端）

SwiftUI 菜单栏应用（Swift Package，Xcode 26 / macOS 14+）：BLE 中心设备 + 自动入网 + 连通性验证。

## 运行

```bash
swift build && swift run
```

菜单栏出现 Wi-Fi 图标 → 点开面板 → 「一键连接手机网络」。

## 配置

编辑 `Sources/OnePlusConnect/Config.swift`：

- `sharedSecret`：须与 Android 端 `AgentConfig.SHARED_SECRET` 一致
- `hotspotSSID`：手机热点 SSID（默认 mmmmmm）
- `wifiPassword`：留空则使用钥匙串中已保存的密码

## 结构

```
Sources/OnePlusConnect/
├── App.swift            # 菜单栏 UI（MenuBarExtra）
├── AppState.swift       # 状态机：搜索 → 开热点 → 入网 → 验证
├── BLECentral.swift     # CBCentralManager 封装（async 接口）
├── HotspotJoiner.swift  # networksetup 入网 + Shell 工具 + 连通性检查
├── Protocol.swift       # 协议编解码（与 android 端 BleProtocol.kt 对应）
└── Config.swift         # 端上配置
```

首启可能弹出蓝牙授权对话框，允许即可。
