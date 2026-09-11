// 設定ウィンドウ（アプリ本体の UI）。
// メニューバーのメニューより詳しい説明つきで同じ設定を編集できる。

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var state: AppState
    @ObservedObject private var updater = Updater.shared
    @ObservedObject private var history = ClipboardHistory.shared

    var body: some View {
        Form {
            Section {
                Picker(L("Hotkey"), selection: hotkeyBinding) {
                    ForEach(AppState.hotkeyPresets) { preset in
                        Text(preset.label).tag(preset.id)
                    }
                }
                .pickerStyle(.segmented)
                Text(L("Focus the target field, press the hotkey, and the clipboard text is typed in."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text(L("Hotkey"))
            }

            Section {
                Picker(L("Typing speed"), selection: $state.intervalMs) {
                    ForEach(AppState.speedPresets, id: \.intervalMs) { preset in
                        Text(preset.label).tag(preset.intervalMs)
                    }
                }
                .pickerStyle(.radioGroup)
                Text(L("Slow down if the target app drops characters (common in remote desktops)."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text(L("Typing"))
            }

            Section {
                Toggle(L("Remote console mode (VNC / VM)"), isOn: $state.keycodeMode)
                Text(L("Presses real key codes instead of sending Unicode text. Turn this on for VNC, remote consoles and VM windows, which otherwise receive every character as \"a\". Only characters on your keyboard layout can be typed this way."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text(L("Compatibility"))
            }

            Section {
                Toggle(
                    L("Keep a clipboard history"),
                    isOn: Binding(
                        get: { history.isEnabled },
                        set: { history.isEnabled = $0 }
                    )
                )
                Text(L("Stores the text you copy, on this Mac only, in your Application Support folder. Items that password managers mark as concealed are skipped. Off by default."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if history.isEnabled {
                    Picker(
                        L("Keep up to"),
                        selection: Binding(
                            get: { history.maxEntries },
                            set: { history.maxEntries = $0 }
                        )
                    ) {
                        ForEach(ClipboardHistory.maxEntriesOptions, id: \.self) { n in
                            Text(L("%d items", n)).tag(n)
                        }
                    }
                    HStack {
                        Text(L("%d items stored", history.entries.count))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button(L("Clear history")) {
                            history.clear()
                        }
                        .disabled(history.entries.isEmpty)
                    }
                }
            } header: {
                Text(L("Clipboard history"))
            }

            Section {
                if state.axTrusted {
                    Label(L("Accessibility permission granted"), systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Label(
                        L("Accessibility permission required — without it macOS discards simulated keystrokes"),
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(.orange)
                    Button(L("Open System Settings…")) {
                        PermissionHelper.openSystemSettings()
                    }
                    // アップデート後は TCC の古いレコードが残り、スイッチを入れ直しても
                    // 効かないことがある（ユーザー報告）。その手順をそのまま案内する。
                    Text(L("If Cliptype is already listed and switching it off and on doesn't help, select the Cliptype row, click the − button to remove it, then click + and add Cliptype again. An update changes the app's signature, and only re-adding the entry records the new one."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button(L("Remove the stale entry for me…")) {
                        PermissionHelper.resetPermissionRecord()
                        PermissionHelper.promptIfNeeded()
                        PermissionHelper.openSystemSettings()
                    }
                }
            } header: {
                Text(L("Permissions"))
            }

            Section {
                Toggle(
                    L("Check for updates automatically"),
                    isOn: Binding(
                        get: { updater.autoCheckEnabled },
                        set: { updater.autoCheckEnabled = $0 }
                    )
                )
                HStack {
                    Button(L("Check Now…")) {
                        Task { @MainActor in await updater.check(userInitiated: true) }
                    }
                    .disabled(updater.status == .checking || updater.status == .downloading)
                    Text(updater.statusDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Text(L("Version %@", Updater.currentVersion))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text(L("Updates"))
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var hotkeyBinding: Binding<String> {
        Binding(
            get: { state.hotkeySelection },
            set: { state.hotkeySelection = $0 }
        )
    }
}
