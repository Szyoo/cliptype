// アプリ全体の状態と設定の永続化（UserDefaults 経由）。
// メニューと設定ウィンドウの両方から同じインスタンスを参照する。

import SwiftUI

/// ホットキーのプリセット。任意キー録音 UI は将来課題とし、まずは定番の組み合わせから選ぶ。
struct HotkeyPreset: Identifiable, Equatable {
    let id: String
    let label: String
    /// Carbon の仮想キーコード
    let keyCode: UInt32
    /// Carbon の修飾キーフラグ（controlKey / shiftKey / optionKey / cmdKey の組み合わせ）
    let modifiers: UInt32
}

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    /// 速度プリセット。Rust CLI の --speed と同じ値に揃えている。
    static let speedPresets: [(label: String, intervalMs: Int)] = [
        ("Fastest (no per-key delay)", 0),
        ("Steady (20 ms per key)", 20),
        ("Careful (50 ms per key)", 50),
    ]

    /// 選べるホットキー。keyCode 9 = V, 11 = B, 35 = P（US 配列の仮想キーコード）
    static let hotkeyPresets: [HotkeyPreset] = [
        HotkeyPreset(
            id: "ctrl-shift-v", label: "⌃⇧V", keyCode: 9,
            modifiers: UInt32(controlKey | shiftKey)
        ),
        HotkeyPreset(
            id: "ctrl-opt-v", label: "⌃⌥V", keyCode: 9,
            modifiers: UInt32(controlKey | optionKey)
        ),
        HotkeyPreset(
            id: "cmd-shift-b", label: "⌘⇧B", keyCode: 11,
            modifiers: UInt32(cmdKey | shiftKey)
        ),
        HotkeyPreset(
            id: "ctrl-shift-p", label: "⌃⇧P", keyCode: 35,
            modifiers: UInt32(controlKey | shiftKey)
        ),
    ]

    @AppStorage("intervalMs") var intervalMs: Int = 0
    @AppStorage("hotkeyPresetId") private var hotkeyPresetId: String = "ctrl-shift-v"

    @Published var isPaused = false

    /// アクセシビリティ権限の現在値。メニュー/設定の表示はこれを参照する。
    /// AXIsProcessTrusted() を直接ビューで呼ぶと、付与後もメニューが
    /// 再評価されず古い表示が残るため、監視付きの @Published にしている。
    @Published private(set) var axTrusted = PermissionHelper.isTrusted()

    private let hotkeyManager = HotkeyManager()
    private var permissionTimer: Timer?

    /// 権限状態の変化（付与・剥奪とも）を定期的に拾ってメニューへ反映する。
    /// AXIsProcessTrusted は極めて軽いので 2 秒間隔のポーリングで十分。
    func startPermissionWatcher() {
        guard permissionTimer == nil else { return }
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            Task { @MainActor in
                let state = AppState.shared
                let trusted = PermissionHelper.isTrusted()
                if trusted != state.axTrusted {
                    state.axTrusted = trusted
                }
                // 「一度でも許可されたことがある」を記録（起動時の自動ダイアログ抑制用）
                if trusted, !UserDefaults.standard.bool(forKey: "hasEverBeenTrusted") {
                    UserDefaults.standard.set(true, forKey: "hasEverBeenTrusted")
                }
            }
        }
    }

    var hotkeyPreset: HotkeyPreset {
        Self.hotkeyPresets.first { $0.id == hotkeyPresetId } ?? Self.hotkeyPresets[0]
    }

    /// 設定ウィンドウからの変更用。再登録まで面倒を見る。
    var hotkeySelection: String {
        get { hotkeyPresetId }
        set {
            hotkeyPresetId = newValue
            activateHotkey()
            objectWillChange.send()
        }
    }

    /// 現在の設定でホットキーを（再）登録する。
    func activateHotkey() {
        let preset = hotkeyPreset
        hotkeyManager.onPressed = { [weak self] in
            Task { @MainActor in
                self?.handleHotkey()
            }
        }
        do {
            try hotkeyManager.register(keyCode: preset.keyCode, modifiers: preset.modifiers)
            NSLog("cliptype: hotkey registered: \(preset.label)")
        } catch {
            NSLog("cliptype: failed to register hotkey: \(error.localizedDescription)")
        }
    }

    private func handleHotkey() {
        NSLog("cliptype: hotkey pressed (paused=\(isPaused))")
        guard !isPaused else { return }
        let interval = intervalMs
        // 数百 ms かかるためメインスレッドを塞がない
        Task.detached(priority: .userInitiated) {
            await Engine.typeClipboard(intervalMs: interval)
        }
    }
}

// Carbon の修飾キー定数を SwiftUI 側でも使えるように import しておく
import Carbon.HIToolbox
