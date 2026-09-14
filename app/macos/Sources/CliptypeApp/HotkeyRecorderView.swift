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
                if recording {
                    Text(L("Press keys…"))
                        .foregroundStyle(Color.accentColor)
                        .frame(minWidth: 140)
                } else {
                    KeyComboChips(combo: combo)
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(recording ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: recording ? 1.5 : 1)
            )
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


/// キーの組み合わせをキーキャップ風のチップで描く（[⌃ Control] + [⇧ Shift] + [V]）。
struct KeyComboChips: View {
    let combo: KeyCombo

    var body: some View {
        HStack(spacing: 5) {
            let parts = combo.parts
            ForEach(Array(parts.enumerated()), id: \.offset) { index, part in
                if index > 0 {
                    Text("+")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                KeycapView(text: part)
            }
        }
    }
}

/// 1 個のキーキャップ。
struct KeycapView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color(nsColor: .windowBackgroundColor))
                    .shadow(color: .black.opacity(0.18), radius: 0, x: 0, y: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .stroke(Color.secondary.opacity(0.4), lineWidth: 1)
            )
    }
}
