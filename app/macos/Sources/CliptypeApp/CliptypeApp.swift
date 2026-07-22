// アプリ本体。メニューバー常駐（MenuBarExtra）+ 設定ウィンドウ（Settings）。
// Dock アイコンは出さない（Info.plist の LSUIElement = true）。

import SwiftUI

@main
struct CliptypeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var state = AppState.shared

    var body: some Scene {
        MenuBarExtra {
            MenuContent()
                .environmentObject(state)
        } label: {
            // 一時停止中はアイコンで分かるようにする
            Image(systemName: state.isPaused ? "keyboard.badge.ellipsis" : "keyboard")
        }

        Settings {
            SettingsView()
                .environmentObject(state)
        }
    }
}

/// 起動時の初期化（ホットキー登録・権限プロンプト）を担う。
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("cliptype: app did finish launching")
        // 初回起動でアクセシビリティ権限のシステムダイアログを出す
        PermissionHelper.promptIfNeeded()
        AppState.shared.startPermissionWatcher()
        AppState.shared.activateHotkey()
    }
}

/// メニューバーのドロップダウン内容。
struct MenuContent: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        Text("cliptype — \(state.hotkeyPreset.label)")

        if !state.axTrusted {
            Button("⚠ Grant Accessibility permission…") {
                PermissionHelper.openSystemSettings()
            }
        }

        Divider()

        Toggle("Pause", isOn: $state.isPaused)

        Picker("Typing speed", selection: $state.intervalMs) {
            ForEach(AppState.speedPresets, id: \.intervalMs) { preset in
                Text(preset.label).tag(preset.intervalMs)
            }
        }

        Divider()

        SettingsLink {
            Text("Settings…")
        }

        Divider()

        Button("Quit cliptype") {
            NSApplication.shared.terminate(nil)
        }
    }
}
