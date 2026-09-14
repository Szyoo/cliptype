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
        (L("Fastest (no per-key delay)"), 0),
        (L("Steady (20 ms per key)"), 20),
        (L("Careful (50 ms per key)"), 50),
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
    /// 実キーコードモード（VNC / リモートコンソール / VM 向け）
    @AppStorage("keycodeMode") var keycodeMode: Bool = false
    @AppStorage("hotkeyPresetId") private var hotkeyPresetId: String = "ctrl-shift-v"

    @Published var isPaused = false

    /// アクセシビリティ権限の現在値。メニュー/設定の表示はこれを参照する。
    /// AXIsProcessTrusted() を直接ビューで呼ぶと、付与後もメニューが
    /// 再評価されず古い表示が残るため、監視付きの @Published にしている。
    @Published private(set) var axTrusted = PermissionHelper.isTrusted()

    /// 起動してから一度も権限を観測できていないか（＝案内を強めに出す条件）。
    @Published private(set) var permissionNeverSeen = !PermissionHelper.isTrusted()

    private let hotkeyManager = HotkeyManager()
    private var permissionTimer: Timer?

    /// 権限状態の変化（付与・剥奪とも）を定期的に拾ってメニューへ反映する。
    ///
    /// 注意: プロセス内の `AXIsProcessTrusted()` は**キャッシュされる**ため、
    /// いくらポーリングしても起動後の変化を観測できない（実測: 許可を取り消しても
    /// true のまま、許可を与えても false のまま）。これが「許可したのにアプリが
    /// 認識しない」というユーザー報告の一因だった。そこで同梱エンジンを新しい
    /// プロセスとして起動して問い合わせる。数 ms の軽い処理だが、無駄打ちを
    /// 避けるため許可済みのときは間隔を空ける。
    func startPermissionWatcher() {
        guard permissionTimer == nil else { return }
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            Task { @MainActor in AppState.shared.pollPermission() }
        }
        // 起動直後にも 1 回だけ正確な値を取り直す
        pollPermission(force: true)
    }

    private var permissionTick = 0

    /// 未許可のときは 2 秒ごと、許可済みのときは 10 秒ごとに確認する。
    private func pollPermission(force: Bool = false) {
        permissionTick += 1
        if !force, axTrusted, permissionTick % 5 != 0 { return }
        Task.detached(priority: .utility) {
            let trusted = PermissionHelper.isTrustedFresh()
            await MainActor.run { AppState.shared.applyTrustState(trusted) }
        }
    }

    fileprivate func applyTrustState(_ trusted: Bool) {
        if trusted != axTrusted {
            axTrusted = trusted
        }
        if trusted {
            permissionNeverSeen = false
            // 「一度でも許可されたことがある」を記録（起動時の自動ダイアログ抑制用）
            if !UserDefaults.standard.bool(forKey: "hasEverBeenTrusted") {
                UserDefaults.standard.set(true, forKey: "hasEverBeenTrusted")
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
        do {
            try hotkeyManager.register(id: 1, keyCode: preset.keyCode, modifiers: preset.modifiers) {
                Task { @MainActor in AppState.shared.handleHotkey() }
            }
            NSLog("cliptype: hotkey registered: \(preset.label)")
        } catch {
            NSLog("cliptype: failed to register hotkey: \(error.localizedDescription)")
        }
        activatePanelHotkey()
    }

    // MARK: - 履歴パネル

    /// 履歴パネルを呼び出すホットキー（H キー = keyCode 4）。
    static let panelHotkeyPresets: [HotkeyPreset] = [
        HotkeyPreset(id: "ctrl-shift-h", label: "⌃⇧H", keyCode: 4, modifiers: UInt32(controlKey | shiftKey)),
        HotkeyPreset(id: "ctrl-opt-h", label: "⌃⌥H", keyCode: 4, modifiers: UInt32(controlKey | optionKey)),
        HotkeyPreset(id: "cmd-shift-h", label: "⌘⇧H", keyCode: 4, modifiers: UInt32(cmdKey | shiftKey)),
    ]

    @AppStorage("panelHotkeyPresetId") private var panelHotkeyPresetId: String = "ctrl-shift-h"

    var panelHotkeyPreset: HotkeyPreset {
        Self.panelHotkeyPresets.first { $0.id == panelHotkeyPresetId } ?? Self.panelHotkeyPresets[0]
    }

    var panelHotkeySelection: String {
        get { panelHotkeyPresetId }
        set {
            panelHotkeyPresetId = newValue
            activatePanelHotkey()
            objectWillChange.send()
        }
    }

    private func activatePanelHotkey() {
        let preset = panelHotkeyPreset
        do {
            try hotkeyManager.register(id: 2, keyCode: preset.keyCode, modifiers: preset.modifiers) {
                Task { @MainActor in HistoryPanelController.shared.toggle() }
            }
            NSLog("cliptype: panel hotkey registered: \(preset.label)")
        } catch {
            NSLog("cliptype: failed to register panel hotkey: \(error.localizedDescription)")
        }
    }

    private func handleHotkey() {
        NSLog("cliptype: hotkey pressed (paused=\(isPaused))")
        guard !isPaused else { return }
        let interval = intervalMs
        let keycode = keycodeMode
        // 数百 ms かかるためメインスレッドを塞がない
        Task.detached(priority: .userInitiated) {
            await Engine.typeClipboard(intervalMs: interval, keycodeMode: keycode)
        }
    }
}

// Carbon の修飾キー定数を SwiftUI 側でも使えるように import しておく
import Carbon.HIToolbox
