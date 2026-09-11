// アクセシビリティ権限まわりのヘルパー。
// 権限はアプリ（責任プロセス）に付与される。子プロセスの cliptype も
// このアプリの権限で動くため、ユーザーが許可するのは Cliptype.app の 1 箇所だけ。

import AppKit
import ApplicationServices

enum PermissionHelper {
    /// プロセス内の判定。**キャッシュされる**ため、起動後の許可/取り消しを
    /// 反映しない（実測: tccutil reset 後も true のまま）。UI の表示には
    /// `isTrustedFresh()` を使い、これは初期値の取得にだけ使う。
    static func isTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    /// 同梱エンジンを新しいプロセスとして起動して権限を問い合わせる。
    /// 新規プロセスは tccd に問い合わせ直すので、現在の状態を正しく返す。
    /// 子プロセスの責任プロセスは本アプリなので、判定対象も本アプリになる。
    static func isTrustedFresh() -> Bool {
        let process = Process()
        process.executableURL = Engine.binaryURL
        process.arguments = ["--check-permission"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            // エンジンを起動できない場合はプロセス内判定にフォールバック
            return isTrusted()
        }
    }

    /// 未許可なら OS のアクセシビリティ許可ダイアログを表示させる。
    static func promptIfNeeded() {
        guard !isTrusted() else { return }
        let options =
            [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    /// システム設定のアクセシビリティのページを開く。
    /// URL スキームは macOS のバージョンで変わるため、順に試して最初に開けたものを使う。
    static func openSystemSettings() {
        let candidates = [
            // macOS 13+（26 / 27 でも解決される）
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
            // 新しい設定アプリの拡張形式
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility",
            // プライバシーのトップ
            "x-apple.systempreferences:com.apple.preference.security?Privacy",
        ]
        for candidate in candidates {
            if let url = URL(string: candidate), NSWorkspace.shared.open(url) {
                return
            }
        }
        // 最後の手段: 設定アプリ自体を開く
        if let settings = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: "com.apple.systempreferences")
        {
            NSWorkspace.shared.openApplication(at: settings, configuration: .init())
        }
    }

    /// このアプリのアクセシビリティ許可レコードを削除する。
    ///
    /// アップデートでバンドルを差し替えると、TCC に残った古いレコードは
    /// **旧バイナリのコード署名指紋のまま**なので、設定画面でスイッチを入れ直しても
    /// 新しいバイナリは一致せず拒否される（ユーザー報告で確認）。レコードごと消せば
    /// 次回の許可時に現在の指紋で作り直される。
    ///
    /// レコードがパス基準で登録されている場合は bundle id 指定では消えないことがある。
    /// その場合は設定画面で − / + する必要があるため、UI 側で必ず手順も案内すること。
    @discardableResult
    static func resetPermissionRecord() -> Bool {
        let bundleID = Bundle.main.bundleIdentifier ?? "io.github.szyoo.cliptype"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        process.arguments = ["reset", "Accessibility", bundleID]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    /// アップデート後に権限が効かないときの手順を出す。
    /// スイッチの入れ直しでは直らず、レコードごと作り直す必要がある。
    @MainActor
    static func presentStaleRecordHelp() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L("Cliptype still doesn't have the Accessibility permission")
        alert.informativeText = L(
            "Updating replaces the app, and macOS ties the old permission to the previous version, so turning the switch off and on does not help.\n\nIn System Settings → Privacy & Security → Accessibility:\n1. Select the Cliptype row\n2. Click − to remove it\n3. Click + and add Cliptype again\n\n\"Remove the entry for me\" does step 2 automatically; you still need to add Cliptype back."
        )
        alert.addButton(withTitle: L("Open System Settings…"))
        alert.addButton(withTitle: L("Remove the entry for me"))
        alert.addButton(withTitle: L("Later"))
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            openSystemSettings()
        case .alertSecondButtonReturn:
            resetPermissionRecord()
            promptIfNeeded()
            openSystemSettings()
        default:
            break
        }
    }

    /// 自分自身を再起動する（許可の反映やクリーンな状態の取り直しに使う）。
    static func relaunchApp() {
        let url = Bundle.main.bundleURL
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }
}
