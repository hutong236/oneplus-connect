import Foundation
import CoreWLAN

/// 子进程执行工具（真超时：到期强制 kill，防止 networksetup 等命令无限挂起）
enum Shell {

    static func run(_ launchPath: String, _ arguments: [String], timeout: TimeInterval = 30) async throws -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: launchPath)
        task.arguments = arguments
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        return try await withCheckedThrowingContinuation { cont in
            do {
                try task.run()
            } catch {
                cont.resume(throwing: error)
                return
            }
            DispatchQueue.global().async {
                // 先读满到 EOF 再等待退出，避免管道缓冲区死锁
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                task.waitUntilExit()
                let text = String(data: data, encoding: .utf8) ?? ""
                if task.terminationReason == .exit, task.terminationStatus == 0 {
                    cont.resume(returning: text)
                } else if task.terminationReason == .exit {
                    cont.resume(throwing: ShellError(cmd: launchPath, code: Int(task.terminationStatus), output: text))
                } else {
                    cont.resume(throwing: ShellError(cmd: launchPath, code: -1, output: "超时（\(Int(timeout))s）被强制终止"))
                }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                if task.isRunning {
                    task.terminate()
                    DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
                        if task.isRunning {
                            kill(task.processIdentifier, SIGKILL)
                        }
                    }
                }
            }
        }
    }

    struct ShellError: LocalizedError {
        let cmd: String
        let code: Int
        let output: String
        var errorDescription: String? { "\(cmd) 退出码 \(code)：\(output.trimmingCharacters(in: .whitespacesAndNewlines))" }
    }
}

/// Wi-Fi 接入：networksetup 优先（密码可来自钥匙串），解析兼容中英文系统
enum HotspotJoiner {

    /// 硬件端口列表解析（兼容中英文系统输出），失败时回退 en0 并用 ipconfig 验证
    static func wifiInterface() async throws -> String {
        if let name = CWWiFiClient.shared().interface()?.interfaceName { return name }
        if let output = try? await Shell.run("/usr/sbin/networksetup", ["-listallhardwareports"]) {
            var lines = output.components(separatedBy: .newlines)
            let portHeader: (String) -> Bool = { line in
                let t = line.trimmingCharacters(in: .whitespaces)
                return t == "Hardware Port: Wi-Fi" || t == "硬件端口: Wi-Fi" || t == "硬件端口：Wi-Fi"
            }
            while let idx = lines.firstIndex(where: portHeader) {
                if let deviceLine = lines[(idx + 1)...].first(where: { $0.hasPrefix("Device:") || $0.hasPrefix("设备:") }) {
                    let dev = deviceLine
                        .replacingOccurrences(of: "Device:", with: "")
                        .replacingOccurrences(of: "设备:", with: "")
                        .trimmingCharacters(in: .whitespaces)
                    if !dev.isEmpty { return dev }
                }
                lines.removeSubrange(idx...)
            }
        }
        // 回退：ipconfig getsummary 输出与系统语言无关
        for iface in ["en0", "en1"] {
            if let summary = try? await Shell.run("/usr/sbin/ipconfig", ["getsummary", iface]),
               summary.contains("SSID"), summary.contains("BSSID") {
                return iface
            }
        }
        throw BleError.connectFailed("未找到 Wi-Fi 硬件端口")
    }

    /// SSID 读取：networksetup（双语）→ ipconfig（与语言无关）；新版 macOS 已移除 airport 工具
    static func currentSSID() async -> String? {
        if let ssid = WiFiOutput.visibleSSID(CWWiFiClient.shared().interface()?.ssid()) { return ssid }
        if let port = try? await wifiInterface(),
           let output = try? await Shell.run("/usr/sbin/networksetup", ["-getairportnetwork", port]) {
            for prefix in ["Current Wi-Fi Network: ", "当前 Wi-Fi 网络：", "当前 Wi-Fi 网络: "] {
                if let range = output.range(of: prefix) {
                    let ssid = String(output[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                    if let visible = WiFiOutput.visibleSSID(ssid) { return visible }
                }
            }
        }
        if let port = try? await wifiInterface(),
           let summary = try? await Shell.run("/usr/sbin/ipconfig", ["getsummary", port]) {
            for line in summary.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                // 实测 macOS 26 输出格式为 "SSID : xxx"，兼容 "= "
                if trimmed.hasPrefix("SSID : ") {
                    let ssid = String(trimmed.dropFirst("SSID : ".count))
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if let visible = WiFiOutput.visibleSSID(ssid) { return visible }
                }
            }
        }
        return nil
    }

    static func join(ssid: String, password: String) async throws {
        // 已在该网络上则不打扰（重连会打断已有关联，拖慢整体时序）
        if await currentSSID() == ssid { return }

        let port = try await wifiInterface()
        _ = try await Shell.run("/usr/sbin/networksetup", ["-setairportpower", port, "on"], timeout: 10)

        // 密码优先级：Config 显式配置 → 钥匙串查询 → 空（无密码加入可能挂起，用超时兜住）
        var pw = password
        if pw.isEmpty {
            pw = await keychainWifiPassword(ssid: ssid) ?? ""
        }

        let arguments = ["-setairportnetwork", port, ssid] + (pw.isEmpty ? [] : [pw])
        let output = try await Shell.run("/usr/sbin/networksetup", arguments, timeout: 30)
        if let failure = WiFiOutput.joinFailure(output) {
            let safeFailure = pw.isEmpty ? failure : failure.replacingOccurrences(of: pw, with: "[密码已隐藏]")
            throw WiFiAccessError.configuration("加入 Wi-Fi 失败：\(safeFailure)。请确认手机热点密码已保存（此密码与 BLE 配对密钥不同）。")
        }
    }

    /// 从钥匙串查询 Wi-Fi 密码（security CLI 可能弹授权框或挂起 → 5 秒硬超时）
    private static func keychainWifiPassword(ssid: String) async -> String? {
        if let password = AppConfig.savedWiFiPassword(ssid: ssid), !password.isEmpty { return password }
        let argsList: [[String]] = [
            ["find-generic-password", "-D", "AirPort Network Password", "-a", ssid, "-w"],
        ]
        for args in argsList {
            if let output = try? await Shell.run("/usr/bin/security", args, timeout: 5),
               !output.isEmpty,
               !output.contains("could not be found") {
                let pw = output.trimmingCharacters(in: .whitespacesAndNewlines)
                if !pw.isEmpty { return pw }
            }
        }
        return nil
    }
}

/// 链路层连通性：默认网关（即手机 wlan0）可达即视为已接入热点
enum ConnectivityCheck {

    struct Verification {
        let wifiInterface: String
        let gateway: String
        let internetReachable: Bool
    }

    static func defaultGateway(interface: String) async -> String? {
        guard let output = try? await Shell.run("/sbin/route", ["-n", "get", "-ifscope", interface, "default"]) else { return nil }
        // 输出包含 "   gateway: 192.168.105.34"
        for line in output.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("gateway:") {
                let value = trimmed.replacingOccurrences(of: "gateway:", with: "")
                    .trimmingCharacters(in: .whitespaces)
                if !value.isEmpty { return value }
            }
        }
        return nil
    }

    static func ping(_ host: String, interface: String) async -> Bool {
        (try? await Shell.run("/sbin/ping", ["-b", interface, "-c", "1", "-W", "2000", host], timeout: 4)) != nil
    }

    static func internetReachable(interface: String) async -> Bool {
        guard let status = try? await Shell.run(
            "/usr/bin/curl",
            ["--interface", interface, "--noproxy", "*", "--connect-timeout", "3", "--max-time", "5",
             "-sS", "-o", "/dev/null", "-w", "%{http_code}",
             "https://www.apple.com/library/test/success.html"],
            timeout: 7
        ) else { return false }
        return status.trimmingCharacters(in: .whitespacesAndNewlines) == "200"
    }

    static func waitUntilOnline(ssid: String, timeout: TimeInterval) async throws -> Verification {
        let deadline = Date().addingTimeInterval(timeout)
        var lastSSID: String? = nil
        var lastGateway: String? = nil
        while Date() < deadline {
            let current = await HotspotJoiner.currentSSID()
            lastSSID = current
            if current == ssid,
               let interface = try? await HotspotJoiner.wifiInterface(),
               let gateway = await defaultGateway(interface: interface),
               await ping(gateway, interface: interface) {
                return Verification(
                    wifiInterface: interface,
                    gateway: gateway,
                    internetReachable: await internetReachable(interface: interface)
                )
            }
            if let interface = try? await HotspotJoiner.wifiInterface(),
               let gateway = await defaultGateway(interface: interface) {
                lastGateway = gateway
            }
            try await Task.sleep(nanoseconds: 1_000_000_000)
        }
        throw BleError.timeout(
            "Wi-Fi 加入/连通性验证超时（\(Int(timeout))s）。当前 SSID=\(lastSSID ?? "不可读取，请检查应用位置权限")，网关=\(lastGateway ?? "无")。请检查热点 Wi-Fi 密码，或先在系统 Wi-Fi 菜单手动连接热点后重试。"
        )
    }
}
