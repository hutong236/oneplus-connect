import Foundation

/// 子进程执行工具
enum Shell {
    @discardableResult
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
                if task.terminationStatus == 0 {
                    cont.resume(returning: text)
                } else {
                    cont.resume(throwing: ShellError(cmd: launchPath, code: Int(task.terminationStatus), output: text))
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
               summary.contains("SSID = ") {
                return iface
            }
        }
        throw BleError.connectFailed("未找到 Wi-Fi 硬件端口")
    }

    /// SSID 读取：networksetup（双语）→ ipconfig（与语言无关）；新版 macOS 已移除 airport 工具
    static func currentSSID() async -> String? {
        if let port = try? await wifiInterface(),
           let output = try? await Shell.run("/usr/sbin/networksetup", ["-getairportnetwork", port]) {
            for prefix in ["Current Wi-Fi Network: ", "当前 Wi-Fi 网络：", "当前 Wi-Fi 网络: "] {
                if let range = output.range(of: prefix) {
                    let ssid = String(output[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !ssid.isEmpty { return ssid }
                }
            }
        }
        if let port = try? await wifiInterface(),
           let summary = try? await Shell.run("/usr/sbin/ipconfig", ["getsummary", port]) {
            for line in summary.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("SSID = ") {
                    let ssid = String(trimmed.dropFirst("SSID = ".count))
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !ssid.isEmpty { return ssid }
                }
            }
        }
        return nil
    }

    static func join(ssid: String, password: String) async throws {
        let port = try await wifiInterface()
        try await Shell.run("/usr/sbin/networksetup", ["-setairportpower", port, "on"])

        var networksetupError: Error?
        do {
            if password.isEmpty {
                // 密码留空：使用钥匙串中已保存的密码（本机曾连过该网络即可）
                try await Shell.run("/usr/sbin/networksetup", ["-setairportnetwork", port, ssid], timeout: 30)
            } else {
                try await Shell.run("/usr/sbin/networksetup", ["-setairportnetwork", port, ssid, password], timeout: 30)
            }
        } catch {
            networksetupError = error
        }

        if let error = networksetupError {
            throw error
        }
    }
}

/// 链路层连通性：默认网关（即手机 wlan0）可达即视为已接入热点
enum ConnectivityCheck {

    static func defaultGateway() async -> String? {
        guard let output = try? await Shell.run("/sbin/route", ["-n", "get", "default"]) else { return nil }
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

    static func ping(_ host: String) -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/sbin/ping")
        task.arguments = ["-c", "1", "-t", "2", host]
        task.standardOutput = Pipe()
        task.standardError = Pipe()
        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch {
            return false
        }
    }

    /// 轮询直到 SSID 匹配且网关可 ping；SSID 读取失败时退化为仅凭网关可达判定
    static func waitUntilOnline(ssid: String, timeout: TimeInterval) async throws -> String {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let current = await HotspotJoiner.currentSSID()
            if (current == nil || current == ssid),
               let gateway = await defaultGateway(),
               ping(gateway) {
                return gateway
            }
            try await Task.sleep(nanoseconds: 1_000_000_000)
        }
        throw BleError.timeout("Wi-Fi 加入/连通性验证超时（\(Int(timeout))s）")
    }
}
