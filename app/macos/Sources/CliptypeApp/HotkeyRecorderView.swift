// ホットキー録音コントロール。
// 「録音」を押すと待ち受け状態になり、次に押された組み合わせ（修飾キー必須）を採用する。
// 録音中は既存のグローバルホットキーを一時解除する（同じ組み合わせを押し直せるように。
// Carbon のホットキーはアプリより先にイベントを横取りするため）。

import AppKit
import SwiftUI

struct HotkeyRecorderView: View {
    let title: String
    @Binding var combo: KeyCombo
    let defaultCombo: KeyCombo
    /// 録音の開始 / 終了をアプリ側へ通知（ホットキーの一時解除・再登録）
    var onRecordingChanged: (Bool) -> Void = { _ in }

    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Button {
                recording ? stopRecording() : startRecording()
            } label: {
                Text(recording ? L("Press keys…") : combo.label)
                    .font(.body.monospaced())
                    .frame(minWidth: 96)
            }
            .buttonStyle(.bordered)
            .tint(recording ? .accentColor : nil)
            .help(L("Click, then press the new shortcut. Esc cancels."))
            if combo != defaultCombo {
                Button(L("Default")) {
                    stopRecording()
                    combo = defaultCombo
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
        }
        .onDisappear { stopRecording() }
    }

    private func startRecording() {
        recording = true
        onRecordingChanged(true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Esc でキャンセル
            if event.keyCode == 53 && event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty {
                stopRecording()
                return nil
            }
            guard let newCombo = KeyCombo(event: event) else {
                // 修飾キー無しは受け付けない（ビープで知らせる）
                NSSound.beep()
                return nil
            }
            combo = newCombo
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if recording {
            recording = false
            onRecordingChanged(false)
        }
    }
}
