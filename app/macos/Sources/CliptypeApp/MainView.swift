// アプリ本体のメインウィンドウ。
// 起動時に表示され、閉じてもメニューバー常駐は続く。Dock クリックで再表示。

import SwiftUI

struct MainView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            SettingsView()
        }
        .frame(minWidth: 440, minHeight: 360)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "keyboard.fill")
                .font(.system(size: 32))
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("Cliptype")
                        .font(.title2.bold())
                    Text("v\(Updater.currentVersion)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(L("Copy text, focus the target field, press %@.", state.hotkeyCombo.label))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if state.isPaused {
                Label(L("Paused"), systemImage: "pause.circle.fill")
                    .foregroundStyle(.orange)
            }
        }
        .padding()
    }
}
