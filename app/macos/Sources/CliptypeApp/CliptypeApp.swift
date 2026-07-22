// アプリ本体。メニューバー常駐（MenuBarExtra）+ 設定ウィンドウ（Settings）。
// Dock アイコンは出さない（Info.plist の LSUIElement = true）。

import SwiftUI

@main
struct CliptypeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var state = AppState.shared

    var body: some Scene {
        // アプリ本体（メインウィンドウ）。閉じても常駐は続き、Dock クリックで再表示される
        WindowGroup("Cliptype", id: "main") {
            MainView()
                .environmentObject(state)
        }
        .windowResizability(.contentSize)

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
        AppState.shared.startPermissionWatcher()
        // システムの許可ダイアログを自動で出すのは「一度も許可されたことがない」
        // 初回だけ。再ビルドで署名が変わって許可が失効した場合などに、起動のたび
        // ダイアログを連発しない（メニューの警告と設定画面から誘導する）。
        if !PermissionHelper.isTrusted(),
            !UserDefaults.standard.bool(forKey: "hasEverBeenTrusted")
        {
            PermissionHelper.promptIfNeeded()
        }
        AppState.shared.activateHotkey()
    }
}

/// メニューバーのドロップダウン内容。
struct MenuContent: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text("cliptype — \(state.hotkeyPreset.label)")

        if !state.axTrusted {
            Button("⚠ Grant Accessibility permission…") {
                PermissionHelper.promptIfNeeded()
                PermissionHelper.openSystemSettings()
            }
        }

        Button("Open Cliptype…") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
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
