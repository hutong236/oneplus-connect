# Root 路径验证工具（2026-10-18 实测用）

以指定身份（shell）通过 `app_process` 直接调用系统 binder 的实验代码，
用于判定无 Root 热点控制可行性。结论见 docs/hotspot-strategies.md。

- `TetherTest.java`：TetheringManager.startTethering（shell 身份，error=14）
- `TetherTest2/6.java`：直连 ITetheringConnector + 伪造 callerPkg（无响应）
- `TetherTest3.java`：原始 tether() 接口（未用上）
- `TetherTest4/5.java`：setWifiApEnabled（已删）/ startTetheredHotspot（权限墙）

编译运行（保留备用，Root 后以 su 运行即为主路径）：

```bash
SDK=/opt/homebrew/share/android-commandlinetools
javac -source 17 -target 17 -cp $SDK/platforms/android-34/android.jar TetherTest.java
$SDK/build-tools/34.0.0/d8 --release --min-api 30 --lib $SDK/platforms/android-34/android.jar *.class --output .
jar cf t.jar classes.dex && adb push t.jar /data/local/tmp/
adb shell "CLASSPATH=/data/local/tmp/t.jar app_process / TetherTest"
```
