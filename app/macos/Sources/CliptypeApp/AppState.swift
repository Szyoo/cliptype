// アプリ全体の状態と設定の永続化（UserDefaults 経由）。
// メニューと設定ウィンドウの両方から同じインスタンスを参照する。

import SwiftUI

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    /// 速度プリセット。Rust CLI の --speed と同じ値に揃えている。
    static let speedPresets: [(label: String, intervalMs: Int)] = [
        (L("Fastest (no per-key delay)"), 0),
        (L("Steady (20 ms per key)"), 20),
        (L("Careful (50 ms per key)"), 50),
    ]

    @AppStorage("intervalMs") var intervalMs: Int = 0
    /// 実キーコードモード（VNC / リモートコンソール / VM 向け）
    @AppStorage("keycodeMode") var keycodeMode: Bool = false

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

    // MARK: - ホットキー（ユーザーが自由に録音）

    @AppStorage("hotkeyCombo") private var hotkeyComboStorage: String = ""
    @AppStorage("panelHotkeyCombo") private var panelHotkeyComboStorage: String = ""
    /// 登録失敗（他アプリと衝突）の表示用
    @Published private(set) var hotkeyError: String?
    @Published private(set) var panelHotkeyError: String?

    /// クリップボードを入力するホットキー（既定 ⌃⇧V）。
    var hotkeyCombo: KeyCombo {
        get { KeyCombo(storageString: hotkeyComboStorage) ?? Self.migratedLegacy("hotkeyPresetId") ?? .defaultType }
        set {
            hotkeyComboStorage = newValue.storageString
            objectWillChange.send()
            activateHotkey()
        }
    }

    /// 履歴パネルを出すホットキー（既定 ⌃⇧H）。
    var panelHotkeyCombo: KeyCombo {
        get { KeyCombo(storageString: panelHotkeyComboStorage) ?? Self.migratedLegacy("panelHotkeyPresetId") ?? .defaultPanel }
        set {
            panelHotkeyComboStorage = newValue.storageString
            objectWillChange.send()
            activatePanelHotkey()
        }
    }

    /// 旧バージョンのプリセット id（UserDefaults）からの移行。
    private static func migratedLegacy(_ key: String) -> KeyCombo? {
        guard let id = UserDefaults.standard.string(forKey: key) else { return nil }
        return KeyCombo(legacyPresetID: id)
    }

    /// 録音中は既存のホットキーを外し、終わったら戻す。
    func suspendHotkeys(_ suspended: Bool) {
        if suspended {
            hotkeyManager.unregister(id: 1)
            hotkeyManager.unregister(id: 2)
        } else {
            activateHotkey()
        }
    }

    /// 現在の設定でホットキーを（再）登録する。
    func activateHotkey() {
        let combo = hotkeyCombo
        do {
            try hotkeyManager.register(id: 1, keyCode: combo.keyCode, modifiers: combo.modifiers) {
                Task { @MainActor in AppState.shared.handleHotkey() }
            }
            hotkeyError = nil
            NSLog("cliptype: hotkey registered: \(combo.label)")
        } catch {
            hotkeyError = L("%@ could not be registered — another app is probably using it. Pick a different shortcut.", combo.label)
            NSLog("cliptype: failed to register hotkey: \(error.localizedDescription)")
        }
        activatePanelHotkey()
    }

    private func activatePanelHotkey() {
        let combo = panelHotkeyCombo
        do {
            try hotkeyManager.register(id: 2, keyCode: combo.keyCode, modifiers: combo.modifiers) {
                Task { @MainActor in HistoryPanelController.shared.toggle() }
            }
            panelHotkeyError = nil
            NSLog("cliptype: panel hotkey registered: \(combo.label)")
        } catch {
            panelHotkeyError = L("%@ could not be registered — another app is probably using it. Pick a different shortcut.", combo.label)
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
