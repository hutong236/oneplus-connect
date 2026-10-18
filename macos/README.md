# OnePlus Connect（macOS 端）

SwiftUI 菜单栏应用（Swift Package，Xcode 26 / macOS 14+）：BLE 中心设备 + 自动入网 + 连通性验证。

## 运行

```bash
cd ..
bash script/build_and_run.sh
```

菜单栏出现 Wi-Fi 图标 → 点开面板 → 「一键连接手机网络」。

这是需要蓝牙和位置权限的菜单栏应用。不要用 `swift run` 做真机联网验证：裸可执行文件没有应用包里的权限说明与应用身份。脚本会生成并启动 `dist/OnePlusConnect.app`，首次连接时请允许位置权限；macOS 使用这项权限控制 SSID 的读取。应用不会请求地理坐标。

只编译和检查应用包而不启动：在仓库根目录运行 `bash script/build_and_run.sh --build-only`。

## 配置

编辑 `Sources/OnePlusConnect/Config.swift`：

- BLE 配对密钥：从 macOS Keychain 读取；需与 Android 应用安全保存的密钥一致，见 `docs/real-device-acceptance.md`
- `hotspotSSID`：手机热点 SSID（默认 mmmmmm）
- `wifiPassword`：可显式配置；更推荐把热点密码存入应用专用 Keychain 条目，避免明文进入源码：

```sh
security add-generic-password -U -s com.hutong.oneplusconnect -a wifi-password:mmmmmm -w
```

输入手机热点的 Wi-Fi 密码，它与 BLE 配对密钥不同。该条目会在每次连接时读取，不需要重新编译。

出现 `SSID=<redacted>` 表示系统隐藏了 SSID，不代表网络真的叫这个名字。请使用应用包启动，并在“系统设置 → 隐私与安全性 → 定位服务”允许 OnePlus Connect。若网关仍是原路由器地址，先在系统 Wi-Fi 菜单手动连接 `mmmmmm` 检查热点密码，再重试应用。

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
