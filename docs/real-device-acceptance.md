# OnePlus Connect V1 真机验收清单

状态：待实机执行。CI 与模拟构建结果不代表 OnePlus 6T 真机通过。

## 配对密钥准备

生成一个至少 32 字节的随机密钥，只在本机安全保存，不要提交到 Git：

```sh
openssl rand -hex 32
```

在 Android 应用的配对密钥栏输入该密钥并保存，应用会使用 Android Keystore 加密保存。macOS 使用相同密钥写入 Keychain：

```sh
security add-generic-password -U -s com.hutong.oneplusconnect -a ble-shared-secret -w
```

BLE 首次写入要求系统建立加密 Bond；在手机和 Mac 上确认配对提示。若密钥未配置或长度不足，Mac 必须拒绝发送控制命令。

Mac 请从仓库根目录运行 `bash script/build_and_run.sh`，以带有权限说明的应用包启动；首次连接允许位置权限以读取真实 SSID。`swift run` 裸程序不用于真机联网验收。

热点 Wi-Fi 密码请单独保存，它不等于 BLE 配对密钥：

```sh
security add-generic-password -U -s com.hutong.oneplusconnect -a wifi-password:mmmmmm -w
```

若显示 `<redacted>`，检查应用位置权限；若网关仍为原路由器地址，检查手机热点 Wi-Fi 密码，先在系统 Wi-Fi 菜单手动连接验证。

## 验收步骤

1. 在 OnePlus 6T Android 11 上安装 Debug APK，打开应用并启动前台服务；确认蓝牙开启、通知常驻。
2. 锁屏等待 10 分钟，从 Mac 菜单栏发起连接；记录发现、配对、热点启动及 Wi-Fi 接入耗时。
3. 检查热点是否开启，Mac 是否显示正确 SSID、Wi-Fi 接口及手机网关；分别确认网关可达和直连互联网状态。
4. 在 macOS 启用与停用 Clash TUN 各测一次；区分手机热点链路状态与代理/互联网出口状态。
5. 点击“断开并关闭热点”；确认热点关闭，且先前连接的 Wi-Fi 网络恢复。
6. 锁屏期间关闭再开启 Mac 蓝牙或离开 BLE 覆盖范围；确认自动重连偏好生效，并记录失败提示。
7. 重启手机并确认启动接收器、前台服务与 BLE 广播状态；在系统杀后台或省电策略下重复锁屏连接。
8. 重放一条已捕获的旧 CMD 帧；确认 Android 拒绝该帧并且热点状态未改变。
9. 记录 Android 版本、Mac/macOS 版本、Root 状态、Clash 模式、每项结果和日志。失败项目写明复现步骤，不标记为通过。

## 结果记录

| 项目 | 结果 | 备注 |
|---|---|---|
| 锁屏 10 分钟后连接 | 待测 | |
| BLE 系统配对及密钥验证 | 待测 | |
| Android 11 Root 热点开启/关闭确认 | 待测 | |
| SSID、接口和网关验证 | 待测 | |
| 直连互联网验证 | 待测 | |
| Clash TUN 开/关 | 待测 | |
| 断开后恢复原 Wi-Fi | 待测 | |
| BLE 丢失后自动重连 | 待测 | |
| 重启后后台广播 | 待测 | |
| 旧帧重放拒绝 | 待测 | |
