// 設定ウィンドウ（アプリ本体の UI）。
// メニューバーのメニューより詳しい説明つきで同じ設定を編集できる。

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var state: AppState

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
                }
            } header: {
                Text(L("Permissions"))
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
