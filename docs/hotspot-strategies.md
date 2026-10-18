# Android 11 热点控制策略（无 Root 优先）

目标：OnePlus 6T（A6010，OxygenOS / Android 11，未 Root、BL 锁定，中国电信）上，让 App 收到 BLE 指令后**自动**开启/关闭可共享网络的热点。

## 实测结论（2026-10-18，真机验证）

| # | 路径 | 调用身份 | 结果 |
|---|---|---|---|
| 1 | `TetheringManager.startTethering`（反射，签名自适应） | App (uid 10037) | 调用成功送达服务端，回 `error=14 ENTITLEMENT_TIMEOUT` ✗ |
| 2 | 同上 + `setExemptFromEntitlementCheck(true)` | App | 仍 error=14（豁免未被服务端认可）✗ |
| 3 | 同上（app_process 实测） | **shell (uid 2000，持有 TETHER_PRIVILEGED)** | 仍 error=14 ✗ |
| 4 | 直连 `ITetheringConnector.startTethering` + 伪造 `callerPkg="com.android.settings"` | shell | 无响应 ✗ |
| 5 | `cmd wifi start-softap` | shell | SecurityException：需 `MAINLINE_NETWORK_STACK` ✗ |
| 6 | `WifiManager.setWifiApEnabled`（反射） | shell | 方法已从该框架删除 ✗ |
| 7 | `WifiManager.startTetheredHotspot`（SoftApConfiguration） | shell | SecurityException：需 `MAINLINE_NETWORK_STACK` ✗ |

**结论：双重墙 —— tethering 侧 entitlement（连 shell 都拦）+ wifi 侧 MAINLINE_NETWORK_STACK。无 Root 无法全自动开启可共享网络的热点。**

可行路线（二选一）：

- **A. Magisk Root（推荐，已获用户预授权）**：解锁 BL（会清数据）→ Magisk → App 用 `su -c` 以 root 身份跑 app_process 调 `startTethering`（root 通过一切检查）。本次实验中的 `TetherTest*.java`（/tmp/tethertest/）即为该路径的验证代码，可移植进 App assets。
- **B. 降级方案**：BLE 收指令后自动拉起热点设置页（当前策略链兜底行为），用户点一下开关。无 Root 但保留一次手动操作。

## 环境坑位记录（同样实测）

- **权限对话框卡锁屏**：App 首启 `requestPermissions` 弹出的系统对话框在锁屏后成为栈顶，阻塞一切后续 intent。修复：`adb shell pm grant <pkg> android.permission.ACCESS_FINE_LOCATION`，或先解锁屏幕。`am start` 需带 `-f 0x10080000`（NEW_TASK|CLEAR_TASK）清理。
- **OPBF（OnePlus Background Freeze）**：后台 App 被 cgroup 冻结，广播静默超时。P1 必须让用户在「电池 → 应用优化」加白名单 + 开启自启动。
- **隐藏 API 可达性**：`TetheringManager` 全家（含 `TetheringRequest$Builder`、`isWifiApEnabled`）反射可达（灰名单）；但 `ConnectivityManager.mTetheringManager` 字段是**黑名单**（denied）。实例获取可用 `context.getSystemService("tethering")`。
- 本机 TetheringManager 实际签名：`startTethering(TetheringManager$TetheringRequest, Executor, StartTetheringCallback)`（TetheringRequest 为嵌套类，与 AOSP 顶层类不同）。
- `ACCESS_WIFI_STATE` 必须声明（普通权限），否则 `isWifiApEnabled` 抛 SecurityException。
- Android 11 无 `svc bluetooth enable`（13+ 才有）、`cmd bluetooth_manager enable` 未实现 → 蓝牙需用户手动开。

## adb 调试通道

```bash
# App 内置（DebugCommandReceiver / MainActivity --ei cmd，与 BLE 同一分发逻辑）
adb shell am start -f 0x10080000 -n com.hutong.oneplusagent/.MainActivity --ei cmd 16   # 16=CONNECT
adb shell am broadcast --receiver-foreground -a com.hutong.oneplusagent.DEBUG_CMD --ei cmd 17
adb logcat -s OnePlusAgent
```
