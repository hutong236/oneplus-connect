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

/// Wi-Fi 接入：networksetup 优先（密码可来自钥匙串），NEHotspotConfiguration 兜底
enum HotspotJoiner {

    /// 从 networksetup 硬件端口列表解析 Wi-Fi 对应的设备名（通常 en0）
    static func wifiInterface() async throws -> String {
        let output = try await Shell.run("/usr/sbin/networksetup", ["-listallhardwareports"])
        var lines = output.components(separatedBy: .newlines)
        while let idx = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "Hardware Port: Wi-Fi" }) {
            if let deviceLine = lines[(idx + 1)...].first(where: { $0.hasPrefix("Device:") }) {
                let dev = deviceLine.replacingOccurrences(of: "Device:", with: "")
                    .trimmingCharacters(in: .whitespaces)
                if !dev.isEmpty { return dev }
            }
            lines.removeSubrange(idx...)
        }
        throw BleError.connectFailed("未找到 Wi-Fi 硬件端口")
    }

    static func currentSSID() async -> String? {
        guard let port = try? await wifiInterface() else { return nil }
        guard let output = try? await Shell.run("/usr/sbin/networksetup", ["-getairportnetwork", port]) else { return nil }
        // 输出形如 "Current Wi-Fi Network: mmmmmm"
        guard let range = output.range(of: "Current Wi-Fi Network: ") else { return nil }
        return String(output[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
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

    /// 轮询直到 SSID 匹配且网关可 ping；返回网关地址
    static func waitUntilOnline(ssid: String, timeout: TimeInterval) async throws -> String {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let current = await HotspotJoiner.currentSSID(), current == ssid,
               let gateway = await defaultGateway(),
               ping(gateway) {
                return gateway
            }
            try await Task.sleep(nanoseconds: 1_000_000_000)
        }
        throw BleError.timeout("Wi-Fi 加入/连通性验证超时（\(Int(timeout))s）")
    }
}
