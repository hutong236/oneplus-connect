# 架构设计

## 组件与职责

```
┌─────────────────────────── Mac ───────────────────────────┐
│  OnePlus Connect (SwiftUI 菜单栏, SPM)                     │
│  ├─ BLE Central      扫描/连接/写指令/订阅状态             │
│  ├─ WiFi Joiner      networksetup / NEHotspotConfiguration │
│  ├─ 连通性检查       默认网关 ping                         │
│  └─ 菜单栏 UI        状态、电量、一键连接、开关项           │
└────────────────────────────┬───────────────────────────────┘
                             │ BLE (GATT, 见 ble-protocol.md)
┌────────────────────────────┴───────────────────────────────┐
│  OnePlus Agent (Kotlin, 前台服务)  OnePlus 6T / Android 11 │
│  ├─ GATT Server      CMD 特征(写) + STATUS 特征(通知)      │
│  ├─ Advertiser       携带 Service UUID 的低延迟广播        │
│  ├─ HotspotController 策略链：反射 startTethering → Root   │
│  │                    → 设置面板兜底                       │
│  └─ 状态监视         热点状态 / 电量 / 移动数据可用性       │
└─────────────────────────────────────────────────────────────┘
```

## 一键连接完整链路

1. Mac 菜单栏点击「一键连接」。
2. BLE Central 连接手机 GATT，写 `CONNECT`（带 nonce + auth）。
3. 手机前台服务校验后执行 HotspotController 策略链开启热点。
4. 热点就绪后通过 STATUS Notify 推送 `{hotspotOn=1, ssid, battery}`。
5. Mac 执行 `networksetup -setairportpower en0 on` + `-setairportnetwork en0 <ssid>`（密码已在钥匙串，无需明文）。
6. 连通性验证：等待 DHCP 完成 → ping 默认网关 → UI 显示「已连接」。

## 后台存活（Android 端，P1 完善）

- 前台服务（`connectedDevice` 类型）+ 常驻通知。
- 电池优化白名单（`REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` 引导）。
- `BOOT_COMPLETED` 自启（Android 11 允许，31+ 需复核限制）。
- BLE 连接断开 + 宽限期（默认 60s）内无重连 → 自动关闭热点省电。

## 与 Clash(TUN) 的关系（P2）

Mac 上 TUN 路由可能覆盖默认网关导致「已连 mmmmmm 但外网走代理」。P2 阶段在连通性检查中区分：
- 链路层验证：ping 网关（192.168.105.34）→ 判定「已接入手机热点」。
- 全网验证：通过代理自身的出口探测，不影响连接判定。

## 安全模型

- v1 共享密钥鉴权（见 ble-protocol.md），防止陌生 BLE 设备操控热点。
- BLE 配对：P0 不强制系统级配对（Just Works 由 GATT 连接承担），P1 评估 bonding。
- Wi-Fi 凭据不经过 BLE 传输：Mac 使用已保存的钥匙串密码直接入网。
