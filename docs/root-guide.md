# Root 刷机手册（OnePlus 6T · HydrogenOS 11.1.2.2 / 34.K.62）

目标：Magisk Root → OnePlus Agent 获得全自动热点控制（P0 闭环）。

## 物资（已备好，~/Downloads/oneplus6t-root/）

| 文件 | 说明 | 校验 |
|---|---|---|
| `twrp-3.5.0_9-0-fajita.img` | 官方 TWRP（临时引导，不刷入） | SHA256 已核对 ✅ |
| `Magisk-v30.7.apk` | 官方 GitHub Release | — |

> 说明：官方全量 OTA 的 CDN（download.h2os.com）已停服，本方案改用 **TWRP 临时引导 + Magisk 原地修补 boot**，无需 boot.img。TWRP 阶段会先把当前 stock boot 分区 dd 备份到电脑，作为日后救砖/重锁的保险。

## 前置状态（已确认）

- 电量 86%（充电中）、fastboot 已装、OEM 解锁开关已开（`oem_unlock_allowed=1`）
- 固件：OnePlus6THydrogen_34.K.62_0620_2112282145（保持不动，无需升降级）

## 流程

### 阶段 1：解锁 Bootloader（自动，⚠️ 此步清空全部数据）

```bash
adb reboot bootloader
fastboot oem unlock        # 设备端出现确认画面（音量键选择，电源键确认）
fastboot reboot
```

> 设备上需要按一次音量键+电源确认（不同 ROM 自动弹确认框）。

### 阶段 2：初始设置（手机端手动，约 5 分钟）

1. 走完开机设置向导（全部可跳过，不必登录账号、可跳过 Wi-Fi）。
2. 设置 → 关于手机 → 版本号连点 7 次开启开发者选项。
3. 开发者选项 → 打开「USB 调试」。
4. 插回 USB 线，手机弹出授权框 → 允许。

### 阶段 3：TWRP 临时引导 + 备份 boot + 装 Magisk（自动）

```bash
adb reboot bootloader
fastboot boot ~/Downloads/oneplus6t-root/twrp-3.5.0_9-0-fajita.img   # 临时引导，不写入

# 备份当前 stock boot（救砖保险，保存为 boot_stock_K62.img）
adb shell dd if=/dev/block/bootdevice/by-name/boot of=/tmp/boot_stock_K62.img
adb pull /tmp/boot_stock_K62.img ~/Downloads/oneplus6t-root/

# 安装 Magisk（APK 即 zip，TWRP 直接装，原地修补 boot 分区）
adb push ~/Downloads/oneplus6t-root/Magisk-v30.7.apk /tmp/magisk.zip
adb shell twrp install /tmp/magisk.zip
adb reboot
```

### 阶段 4：手机端收尾（手动，约 2 分钟）

1. 打开 Magisk 应用一次（如提示安装完成/额外组件，确认）。
2. 安装 OnePlus Agent（`adb install -r app-debug.apk`）。
3. 测试「开启热点」→ Magisk 弹 su 授权 → **允许**（可勾选记住）。
4. 顺手做掉 P1 需要的白名单：设置 → 电池 → 应用优化 → OnePlus Agent 不优化；应用信息 → 自启动允许。
5. 打开蓝牙（Android 11 无法 adb 开启）。

### 阶段 5：P0 验收（自动）

```bash
adb shell am start -f 0x10080000 -n com.hutong.oneplusagent/.MainActivity --ei cmd 16
adb logcat -s OnePlusAgent     # 期待：策略2 Root 成功 → 热点自动开启
```

然后 Mac 端 `cd macos && swift run` 走完整链路。

## 风险与回退

- **数据全清**：解锁即恢复出厂。照片/微信/短信先备份。
- **Root 检测**：部分银行/支付类应用可能检测 Root。Magisk 设置里开 Zygisk + DenyList 可隐藏多数检测。
- **救砖**：保留 `boot_stock_K62.img`；`fastboot boot twrp` 后可随时恢复或重刷。若要重新上锁 BL（`fastboot oem lock`），必须先恢复 stock boot 并确保系统原版，否则有变砖风险。
- 整个流程不刷写任何分区（TWRP 仅临时引导；Magisk 修补的是 boot 且有 dd 备份），风险可控。

## 实际执行记录（2026-10-18/19，已完成 ✅）

- 解锁：`fastboot oem unlock` 返回 OKAY 后**需在手机上音量+电源确认**，且必须先在开发者选项打开「OEM 解锁」（`settings put` 无效，标志存持久分区）。
- TWRP 官方 3.5.0_9-0 在本机引导即 CrashDump（init 崩溃）；**改用 `TWRP-3.6.2_11-OP6xT.img`（SourceForge oneplus-6-series 项目，SIDDK 构建）一次成功**。
- SourceForge 主站/多数镜像对代理 IP 403/Cloudflare 盾；deac-riga 镜像最终由手机浏览器直接下载（用户手动传回 Mac）。
- Magisk v30.7 经 TWRP `twrp install` 安装成功（检测 Stock boot → 修补 → 写回 boot_b）。
- recovery 安装的 Magisk 应用是占位版（首开会联网下载完整版，国内慢）；**直接 `adb install -r Magisk-v30.7.apk` 离线替换即可**。
- 首次 su 授权注意：`su -c id` 有 30s 超时，弹窗需**当次有效期内**点允许；永久授权走 Magisk 应用 → 超级用户。
- **验收结果**：`cmd=16` → 策略2 Root → `onTetheringStarted`（error=14 消失）→ wlan0 UP + DHCP（192.168.6.x）；`cmd=17` → 热点关闭。**P0 热点自动控制闭环达成。**
- 清数据副作用：热点 SSID/密码恢复出厂默认，需在手机设置里改回 `mmmmmm` 及原密码，Mac 端钥匙串密码才能复用。
