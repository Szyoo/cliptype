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
        .defaultSize(width: 480, height: 640)
        .windowResizability(.contentMinSize)

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
        // アップデート直後は署名が変わって権限が失効しているので、一度だけ出し直す
        let afterUpdate = UserDefaults.standard.bool(forKey: "promptPermissionOnNextLaunch")
        if !PermissionHelper.isTrusted(),
            afterUpdate || !UserDefaults.standard.bool(forKey: "hasEverBeenTrusted")
        {
            PermissionHelper.promptIfNeeded()
        }
        UserDefaults.standard.removeObject(forKey: "promptPermissionOnNextLaunch")
        AppState.shared.activateHotkey()
        Updater.shared.scheduleAutomaticChecks()
        // クリップボード履歴（既定オフ。有効化したユーザーだけ監視が動く）
        ClipboardHistory.shared.startIfEnabled()

        // アップデート直後に権限が戻らない場合（TCC の古いレコードが残っている）、
        // 放置すると「許可したのに動かない」状態になるので手順を明示する。
        if afterUpdate {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(12))
                if !AppState.shared.axTrusted {
                    PermissionHelper.presentStaleRecordHelp()
                }
            }
        }
    }
}

/// メニューバーのドロップダウン内容。
struct MenuContent: View {
    @EnvironmentObject private var state: AppState
    @ObservedObject private var history = ClipboardHistory.shared
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text("cliptype \(Updater.currentVersion) — \(state.hotkeyPreset.label)")

        if !state.axTrusted {
            // 設定画面に詳しい手順（古いレコードの削除）があるのでそちらへ誘導する
            Button(L("⚠ Grant Accessibility permission…")) {
                PermissionHelper.promptIfNeeded()
                PermissionHelper.openSystemSettings()
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }
        }

        Button(L("Open Cliptype…")) {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }

        Divider()

        Toggle(L("Pause"), isOn: $state.isPaused)

        Picker(L("Typing speed"), selection: $state.intervalMs) {
            ForEach(AppState.speedPresets, id: \.intervalMs) { preset in
                Text(preset.label).tag(preset.intervalMs)
            }
        }

        Toggle(L("Remote console mode (VNC / VM)"), isOn: $state.keycodeMode)

        // 履歴の仮 UI（サブメニュー）。最終的な形（ポップアップ等）は別途決める。
        // 項目を選ぶとクリップボードへ戻す → いつものホットキーで入力できる。
        if history.isEnabled {
            Menu(L("Clipboard history")) {
                if history.entries.isEmpty {
                    Text(L("No items yet"))
                } else {
                    ForEach(history.entries.prefix(15)) { entry in
                        Button(entry.preview) {
                            history.copyToPasteboard(entry)
                        }
                    }
                    Divider()
                    Button(L("Clear history")) {
                        history.clear()
                    }
                }
            }
        }

        Divider()

        SettingsLink {
            Text(L("Settings…"))
        }

        Button(L("Check for Updates…")) {
            Task { @MainActor in await Updater.shared.check(userInitiated: true) }
        }

        Divider()

        Button(L("Quit cliptype")) {
            NSApplication.shared.terminate(nil)
        }
    }
}
