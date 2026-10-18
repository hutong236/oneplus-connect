import SwiftUI

@main
struct OnePlusConnectApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var state = AppState()

    var body: some Scene {
        MenuBarExtra("OnePlus Connect", systemImage: "wifi") {
            MenuBarView()
                .environmentObject(state)
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 纯菜单栏应用：不占 Dock 栏
        NSApp.setActivationPolicy(.accessory)
    }
}

struct MenuBarView: View {
    @EnvironmentObject private var state: AppState

    // P1 再接入实际行为，当前仅持久化偏好
    @AppStorage("autoConnect") private var autoConnect = true
    @AppStorage("autoReconnect") private var autoReconnect = true
    @AppStorage("hotspotOffOnExit") private var hotspotOffOnExit = true

    private var statusColor: Color {
        switch state.phase {
        case .connected: return .green
        case .failed: return .red
        case .idle: return .secondary
        default: return .orange
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Circle().fill(statusColor).frame(width: 8, height: 8)
                Text("OnePlus 6T").font(.headline)
            }

            Text(state.phase.label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            HStack(spacing: 12) {
                if let battery = state.battery {
                    Label("\(battery)%", systemImage: "battery.75")
                }
                if state.hotspotOn {
                    Label("热点已开", systemImage: "personalhotspot")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Button {
                state.connect()
            } label: {
                Text(state.phase.isRunning ? "连接中 …" : "一键连接手机网络")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .keyboardShortcut(.return)
            .disabled(state.phase.isRunning)

            Divider()

            Toggle("自动连接", isOn: $autoConnect)
            Toggle("断线自动重连", isOn: $autoReconnect)
            Toggle("断开时关闭热点", isOn: $hotspotOffOnExit)

            Divider()

            Button("断开并关闭热点") {
                state.disconnect()
            }
            .disabled(state.phase.isRunning || state.phase == .idle)

            if !state.log.isEmpty {
                Divider()
                ScrollView {
                    Text(state.log.suffix(6).joined(separator: "\n"))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 72)
            }

            Divider()
            Button("退出") { NSApp.terminate(nil) }
        }
        .padding(14)
        .frame(minWidth: 250)
    }
}
