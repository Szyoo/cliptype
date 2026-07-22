// 同梱の Rust バイナリ（cliptype）を入力エンジンとして呼び出す。
// タイピングの実装（IME 迂回・末尾フラッシュ待ち・改行/タブ処理）は
// Rust 側に一元化されているため、Swift 側では再実装しない。

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

    /// ホットキーの修飾キーが離されるのを待ってから、クリップボードを鍵入する。
    static func typeClipboard(intervalMs: Int) async {
        waitModifiersReleased()

        let process = Process()
        process.executableURL = binaryURL
        process.arguments = ["--delay", "0", "--interval", String(intervalMs)]
        // クリップボード内容を含みうる出力は捨てる（ログに残さない）
        process.standardOutput = FileHandle.nullDevice
        let stderrPipe = Pipe()
        process.standardError = stderrPipe

        do {
            try process.run()
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
