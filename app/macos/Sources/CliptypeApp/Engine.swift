// 同梱の Rust バイナリ（cliptype）を入力エンジンとして呼び出す。
// タイピングの実装（IME 迂回・末尾フラッシュ待ち・改行/タブ処理・実キーコード
// モード）は Rust 側に一元化されているため、Swift 側では再実装しない。

import AppKit
import Foundation

enum Engine {
    /// 同梱バイナリの場所。開発時（swift run / swift build 直実行）は
    /// CLIPTYPE_BIN 環境変数か、リポジトリの target/release へフォールバックする。
    static var binaryURL: URL {
        if let override = ProcessInfo.processInfo.environment["CLIPTYPE_BIN"] {
            return URL(fileURLWithPath: override)
        }
        let bundled = Bundle.main.bundleURL
            .appendingPathComponent("Contents/MacOS/cliptype")
        if FileManager.default.isExecutableFile(atPath: bundled.path) {
            return bundled
        }
        // 開発フォールバック: <repo>/app/macos/.build/... から見た target/release
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // CliptypeApp
            .deletingLastPathComponent() // Sources
            .deletingLastPathComponent() // macos
            .deletingLastPathComponent() // app
            .appendingPathComponent("target/release/cliptype")
    }

    /// クリップボードの内容を鍵入する（ホットキーの既定動作）。
    static func typeClipboard(intervalMs: Int, keycodeMode: Bool) async {
        await run(stdinText: nil, intervalMs: intervalMs, keycodeMode: keycodeMode)
    }

    /// 任意のテキストを鍵入する（クリップボード履歴の項目など）。
    /// テキストは引数ではなく標準入力で渡すので、`ps` 等に内容が漏れない。
    static func typeText(_ text: String, intervalMs: Int, keycodeMode: Bool) async {
        await run(stdinText: text, intervalMs: intervalMs, keycodeMode: keycodeMode)
    }

    /// ホットキーの修飾キーが離されるのを待ってからエンジンを起動する。
    private static func run(stdinText: String?, intervalMs: Int, keycodeMode: Bool) async {
        waitModifiersReleased()

        let process = Process()
        process.executableURL = binaryURL
        var arguments = [
            "--delay", "0",
            "--interval", String(intervalMs),
            // VNC / リモートコンソールは添付 Unicode を無視するため実キーコードで送る
            "--mode", keycodeMode ? "keycode" : "unicode",
        ]
        if stdinText != nil {
            arguments.append("--stdin")
        }
        process.arguments = arguments
        // クリップボード内容を含みうる出力は捨てる（ログに残さない）
        process.standardOutput = FileHandle.nullDevice
        let stderrPipe = Pipe()
        process.standardError = stderrPipe
        let stdinPipe = stdinText.map { _ in Pipe() }
        if let stdinPipe { process.standardInput = stdinPipe }

        do {
            try process.run()
            if let stdinPipe, let text = stdinText {
                // エンジンは起動直後に stdin を全部読むので、書き切ってから閉じる
                stdinPipe.fileHandleForWriting.write(Data(text.utf8))
                try? stdinPipe.fileHandleForWriting.close()
            }
            process.waitUntilExit()
            if process.terminationStatus != 0 {
                let data = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                let message = String(data: data, encoding: .utf8) ?? ""
                NSLog("cliptype engine failed (%d): %@", process.terminationStatus, message)
            }
        } catch {
            NSLog("cliptype engine could not start: %@", error.localizedDescription)
        }
    }

    /// 物理修飾キー（⌃⇧⌥⌘）が全て離されるまで待つ（上限 2 秒 + 50ms の余裕）。
    /// 押されたままだと合成キーイベントに修飾が混ざってしまう。
    private static func waitModifiersReleased() {
        let mask: CGEventFlags = [.maskShift, .maskControl, .maskAlternate, .maskCommand]
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            let flags = CGEventSource.flagsState(.hidSystemState)
            if flags.intersection(mask).isEmpty { break }
            usleep(20_000)
        }
        usleep(50_000)
    }
}
