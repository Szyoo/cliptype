// 設定ウィンドウ（アプリ本体の UI）。
// メニューバーのメニューより詳しい説明つきで同じ設定を編集できる。

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        Form {
            Section {
                Picker("Hotkey", selection: hotkeyBinding) {
                    ForEach(AppState.hotkeyPresets) { preset in
                        Text(preset.label).tag(preset.id)
                    }
                }
                .pickerStyle(.segmented)
                Text("Focus the target field, press the hotkey, and the clipboard text is typed in.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Hotkey")
            }

            Section {
                Picker("Typing speed", selection: $state.intervalMs) {
                    ForEach(AppState.speedPresets, id: \.intervalMs) { preset in
                        Text(preset.label).tag(preset.intervalMs)
                    }
                }
                .pickerStyle(.radioGroup)
                Text("Slow down if the target app drops characters (common in remote desktops).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Typing")
            }

            Section {
                if PermissionHelper.isTrusted() {
                    Label("Accessibility permission granted", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Label(
                        "Accessibility permission required — without it macOS discards simulated keystrokes",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(.orange)
                    Button("Open System Settings…") {
                        PermissionHelper.openSystemSettings()
                    }
                }
            } header: {
                Text("Permissions")
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
