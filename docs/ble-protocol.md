# BLE 通信协议（v2）

两端（macOS / Android）共同遵守的 GATT 契约。**修改本文件必须同步两端 `Protocol.swift` / `BleProtocol.kt`。**

角色：Mac = BLE 中心设备（Central）；OnePlus 6T = BLE 外设（Peripheral，GATT Server + Advertiser）。

## GATT 结构

| 项目 | UUID | 属性 |
|---|---|---|
| Service | `7b6e0001-2a4c-4e6d-9b8a-5f1e3d5c7a9b` | — |
| CMD 特征 | `7b6e0002-2a4c-4e6d-9b8a-5f1e3d5c7a9b` | Write（Mac → 手机） |
| STATUS 特征 | `7b6e0003-2a4c-4e6d-9b8a-5f1e3d5c7a9b` | Read + Notify（手机 → Mac） |

广播：AD 数据携带 Service UUID（128-bit），便于 Mac 定向扫描；本地名 `OnePlus Agent`。

## 配对与鉴权

首次写 CMD 时，GATT 要求系统加密并进行 MITM 保护的 Bond。Android 仅接受已 Bond 的客户端。
应用层 HMAC 密钥由用户在两端安全配置：Android 使用 Gradle 本机属性注入后加密保存至 Android Keystore；
macOS 从 Keychain 读取。密钥至少 32 个 UTF-8 字节，不能提交到仓库。

每条 CMD 使用 `HMAC-SHA256(key, nonce_le ‖ cmd)[0..15]`。Nonce 由 Unix 毫秒时间戳和 16 位随机数组成；
Android 按 Bond 设备持久保存最近接受的时间戳，拒绝重复、过期（5 分钟）和过度超前（30 秒）的帧。

## CMD 帧（写入 CMD 特征，固定 26 字节）

```
偏移  长度  字段
0     1    version = 0x02
1     1    cmd
2     8    nonce（小端 uint64）
10    16   HMAC（见上，截断到 16 字节）
```

| cmd 值 | 名称 | 含义 |
|---|---|---|
| 0x01 | PING | 心跳/连通测试，手机立即回一条 STATUS |
| 0x10 | CONNECT | 开启热点（等待就绪后回 STATUS） |
| 0x11 | DISCONNECT | 关闭热点 |
| 0x20 | GET_STATUS | 查询当前状态 |

## STATUS 帧（Notify / Read）

```
偏移  长度  字段
0     1    version = 0x02
1     1    flags
2     1    batteryPercent（0–100，未知=0xFF）
3     1    ssidLen N（0 表示不携带）
4     N    ssid（UTF-8）
```

flags 位定义：

| 位 | 名称 | 含义 |
|---|---|---|
| bit0 | HOTSPOT_ON | 热点已开启 |
| bit1 | UPSTREAM_OK | 移动数据可用（有上行网络） |
| bit2 | CMD_FAILED | 最近一条指令执行失败（含鉴权失败） |

## 连接时序（P0 主链路）

```
Mac                                OnePlus 6T
 │── 扫描 Service UUID ──────────────→│ (BLE 广播)
 │── 建立连接 / 发现服务/特征 ───────→│
 │── 订阅 STATUS Notify ─────────────→│
 │── 写 CMD{CONNECT, nonce, auth} ───→│ 校验 → 开热点
 │←──── STATUS{hotspotOn=1, ssid} ────│ (就绪后推送)
 │   加入 Wi-Fi(SSID) → 连通性验证
 │── 写 CMD{PING} 周期心跳 ──────────→│
 │   （断开 BLE 且超过宽限期 → 手机自动关热点）
```

## 错误与超时建议

- Mac 写 CMD 前系统必须完成 Bond；密钥未配置时拒绝发送。
- Mac 写 CMD 后 15s 内未收到 `HOTSPOT_ON` 视为失败，提示用户查看手机。
- 手机端执行 CONNECT 若所有策略失败，置 `CMD_FAILED` 并回 STATUS。
