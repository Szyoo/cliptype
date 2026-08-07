// ローカライズ用ヘルパー。
// SwiftPM モジュールのリソースバンドル（Bundle.module）から文字列を引く。
// キーは英語の原文そのもの（未翻訳・未知の言語では英語がそのまま出る）。

import Foundation

/// ローカライズされた文字列を返す。
func L(_ key: String) -> String {
    NSLocalizedString(key, bundle: .module, comment: "")
}

/// フォーマット引数つき。
func L(_ key: String, _ args: CVarArg...) -> String {
    String(format: L(key), arguments: args)
}
