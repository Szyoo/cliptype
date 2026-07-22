// アクセシビリティ権限まわりのヘルパー。
// 権限はアプリ（責任プロセス）に付与される。子プロセスの cliptype も
// このアプリの権限で動くため、ユーザーが許可するのは Cliptype.app の 1 箇所だけ。

import AppKit
import ApplicationServices

enum PermissionHelper {
    /// 現在の権限状態。
    static func isTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    /// 未許可なら OS のアクセシビリティ許可ダイアログを表示させる。
    static func promptIfNeeded() {
        guard !isTrusted() else { return }
        let options =
            [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    /// システム設定のアクセシビリティのページを開く。
    static func openSystemSettings() {
        let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        )!
        NSWorkspace.shared.open(url)
    }
}
