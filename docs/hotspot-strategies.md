# Android 11 热点控制策略（无 Root 优先）

目标：OnePlus 6T（A6010，OxygenOS / Android 11，未 Root、BL 锁定）上，让 App 收到 BLE 指令后**自动**开启/关闭 Wi-Fi 共享热点。

公开 SDK 中没有开关热点的 API（`setWifiApEnabled` 自 API 25 起隐藏）。策略链按优先级依次尝试：

## 策略 1：反射调用 `ConnectivityManager.startTethering`（无 Root 首选）

```kotlin
// 隐藏签名：startTethering(int type, boolean showProvisioningUi,
//                          OnStartTetheringCallback callback, Handler handler)
// type: TETHERING_WIFI = 0
```

- 属于灰名单（unsupported 但非禁止）隐藏 API，Android 11 上反射调用通常不被拦截。
- `OnStartTetheringCallback` 是隐藏抽象类，普通编译无法继承；实际以 `null` 回调调用，
  **用 `WifiManager.isWifiApEnabled()`（反射）轮询 10s 确认结果**。
- OxygenOS 定制可能收窄，真机实测为准 —— 这正是 P0 的核心验证点。
- 验证命令（adb，无需 App）：

```bash
adb shell dumpsys tethering | head -30          # 查看热点/tether 状态
adb shell svc data enable                        # 确保移动数据在
```

## 策略 2：Root / 系统权限通道（预留）

当前设备未 Root，代码保留接口。若日后 Magisk：

```bash
su -c cmd wifi start-softap ap0     # Android 11 wifi shell（不同 ROM 命令有差异）
```

或借助 root 授予 App `WRITE_SETTINGS` + `TETHER_PRIVILEGED` 的变通方案，届时再定。

## 策略 3：设置面板兜底（需手动点一下）

```kotlin
startActivity(Intent("android.settings.TETHER_SETTINGS"))
```

无法全自动，但保证功能可达：BLE 收到指令后自动拉起热点设置页，用户一次点击完成。
App 内测试按钮也直接提供该入口。

## 热点状态读取（与策略配合）

`WIFI_AP_STATE_CHANGED` 受保护广播允许接收；AP 开关状态经 `WifiManager.getWifiApState()`
（反射，隐藏）轮询。SSID 默认取配置常量 `mmmmmm`（热点由系统设置创建，名称不变）。

## 结论与风险

| 风险 | 影响 | 缓解 |
|---|---|---|
| startTethering 被 OxygenOS 拦截（SecurityException） | 策略 1 失败 | 降级策略 2/3；评估 Root |
| 隐藏 API 在后续 OTA 变黑名单 | 升级后失效 | 锁定系统版本；或 Magisk |
| startTethering 开的是「网络共享」而非「热点」 | 共享的是 USB/蓝牙 | type 固定 `TETHERING_WIFI(0)`，实测确认 |

P0 验收：`adb logcat -s OnePlusAgent` 观察策略链日志，Mac 发 CONNECT 后 15s 内热点自动开启。
