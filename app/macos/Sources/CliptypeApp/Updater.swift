// アプリ内アップデート。
// GitHub Releases の latest を問い合わせ、macOS アプリ zip をダウンロード →
// sha256 検証 → 展開 → 差し替え → 再起動する。
//
// Sparkle を使わない理由: EdDSA 鍵と appcast フィードの運用が必要で、現状の
// ad-hoc 署名 + GitHub Releases のパイプラインには重すぎる。リリース成果物には
// 既に .sha256 が付いているので、それを検証に使う。
//
// 制約（Developer ID 署名を導入するまで）: 差し替え後は署名が変わるため
// アクセシビリティ権限が失効する。インストーラ側で TCC の古い項目を消し、
// 再起動後に許可ダイアログを出し直す。

import AppKit
import CryptoKit
import Foundation

@MainActor
final class Updater: ObservableObject {
    static let shared = Updater()

    /// GitHub リポジトリ（owner/name）
    private let repo = "Szyoo/cliptype"
    /// macOS アプリ成果物のファイル名末尾（release.yml と揃える）
    private let assetSuffix = "-macos-app-universal.zip"

    enum Status: Equatable {
        case idle
        case checking
        case upToDate(Date)
        case available(Release)
        case downloading
        case readyToInstall(Release)
        case failed(String)
    }

    struct Release: Equatable {
        /// "0.1.1"（先頭の v を除いたもの）
        let version: String
        let tag: String
        let notes: String
        let zipURL: URL
        let sha256URL: URL?
        let pageURL: URL
    }

    enum UpdateError: LocalizedError {
        case noAsset
        case badResponse
        case checksumMismatch
        case notWritable(String)
        case extractFailed

        var errorDescription: String? {
            switch self {
            case .noAsset: return L("No macOS app package was found in the latest release.")
            case .badResponse: return L("GitHub returned an unexpected response.")
            case .checksumMismatch: return L("The downloaded file failed verification.")
            case .notWritable:
                return L("The application folder is not writable. Move Cliptype to your Applications folder and try again.")
            case .extractFailed: return L("The downloaded archive could not be extracted.")
            }
        }
    }

    @Published private(set) var status: Status = .idle

    private var timer: Timer?

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    var autoCheckEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "autoCheckUpdates") as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: "autoCheckUpdates")
            objectWillChange.send()
            scheduleAutomaticChecks()
        }
    }

    // MARK: - 自動チェック

    /// 起動時に呼ぶ: 数秒後に静かに確認し、その後は 24 時間ごとに繰り返す。
    func scheduleAutomaticChecks() {
        timer?.invalidate()
        timer = nil
        guard autoCheckEnabled else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(5))
            await check(userInitiated: false)
        }
        timer = Timer.scheduledTimer(withTimeInterval: 24 * 3600, repeats: true) { _ in
            Task { @MainActor in
                await Updater.shared.check(userInitiated: false)
            }
        }
    }

    // MARK: - チェック

    func check(userInitiated: Bool) async {
        switch status {
        case .checking, .downloading, .readyToInstall: return
        default: break
        }
        status = .checking
        do {
            let release = try await fetchLatest()
            let skipped = UserDefaults.standard.string(forKey: "skippedUpdateVersion")
            let newer = Self.isNewer(release.version, than: Self.currentVersion)
            if newer, userInitiated || release.version != skipped {
                status = .available(release)
                presentUpdateAlert(release)
            } else {
                status = .upToDate(Date())
                if userInitiated { presentUpToDateAlert() }
            }
        } catch {
            status = .failed(error.localizedDescription)
            if userInitiated { presentErrorAlert(error) }
        }
    }

    private struct LatestResponse: Decodable {
        struct Asset: Decodable {
            let name: String
            let browser_download_url: URL
        }
        let tag_name: String
        let body: String?
        let html_url: URL
        let assets: [Asset]
    }

    private func fetchLatest() async throws -> Release {
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("cliptype-updater/\(Self.currentVersion)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw UpdateError.badResponse
        }
        let latest = try JSONDecoder().decode(LatestResponse.self, from: data)
        guard let zip = latest.assets.first(where: { $0.name.hasSuffix(assetSuffix) }) else {
            throw UpdateError.noAsset
        }
        let sha = latest.assets.first(where: { $0.name == zip.name + ".sha256" })
        let version = latest.tag_name.hasPrefix("v") ? String(latest.tag_name.dropFirst()) : latest.tag_name
        return Release(
            version: version,
            tag: latest.tag_name,
            notes: latest.body ?? "",
            zipURL: zip.browser_download_url,
            sha256URL: sha?.browser_download_url,
            pageURL: latest.html_url
        )
    }

    /// セマンティックバージョン比較（"0.1.10" > "0.1.9"）。
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        func parts(_ s: String) -> [Int] {
            s.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
        }
        let a = parts(candidate)
        let b = parts(current)
        let n = max(a.count, b.count)
        for i in 0..<n {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    // MARK: - ダウンロード・検証・展開

    func downloadAndPrepare(_ release: Release) async {
        status = .downloading
        do {
            let work = FileManager.default.temporaryDirectory
                .appendingPathComponent("cliptype-update-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)

            let (downloaded, _) = try await URLSession.shared.download(from: release.zipURL)
            let zip = work.appendingPathComponent("update.zip")
            try FileManager.default.moveItem(at: downloaded, to: zip)

            // sha256 検証（成果物と同じリリースに付いている .sha256 と照合）
            if let shaURL = release.sha256URL {
                let (shaData, _) = try await URLSession.shared.data(from: shaURL)
                let expected = String(decoding: shaData, as: UTF8.self)
                    .split(whereSeparator: { $0 == " " || $0 == "\n" }).first.map(String.init) ?? ""
                let actual = SHA256.hash(data: try Data(contentsOf: zip))
                    .map { String(format: "%02x", $0) }.joined()
                guard expected.lowercased() == actual else { throw UpdateError.checksumMismatch }
            }

            // 展開（ditto は .app のリソースフォークやシンボリックリンクを正しく保つ）
            let extractDir = work.appendingPathComponent("extract")
            try run("/usr/bin/ditto", ["-x", "-k", zip.path, extractDir.path])
            guard let newApp = try FileManager.default.contentsOfDirectory(
                at: extractDir, includingPropertiesForKeys: nil
            ).first(where: { $0.pathExtension == "app" }) else {
                throw UpdateError.extractFailed
            }

            pendingInstall = newApp
            status = .readyToInstall(release)
            presentReadyAlert(release)
        } catch {
            status = .failed(error.localizedDescription)
            presentErrorAlert(error)
        }
    }

    private var pendingInstall: URL?

    // MARK: - インストール（差し替え → 再起動）

    /// 自分を終了し、ヘルパースクリプトが古いバンドルを新しいものに置き換えて再起動する。
    func installAndRelaunch() {
        guard let newApp = pendingInstall else { return }
        let current = Bundle.main.bundleURL
        let parent = current.deletingLastPathComponent()
        // 安全装置: .app 以外や書き込めない場所は触らない
        guard current.pathExtension == "app",
            FileManager.default.isWritableFile(atPath: parent.path)
        else {
            let err = UpdateError.notWritable(current.path)
            status = .failed(err.localizedDescription)
            presentErrorAlert(err)
            return
        }

        // 再起動後に権限ダイアログを出し直す（署名が変わって失効するため）
        UserDefaults.standard.set(true, forKey: "promptPermissionOnNextLaunch")

        let script = """
            #!/bin/bash
            # cliptype 更新ヘルパー: 旧プロセスの終了を待って差し替え、再起動する
            PID="$1"; OLD="$2"; NEW="$3"; WORK="$4"
            for _ in $(seq 1 150); do
                kill -0 "$PID" 2>/dev/null || break
                sleep 0.2
            done
            case "$OLD" in *.app) ;; *) exit 1 ;; esac
            rm -rf "$OLD"
            mv "$NEW" "$OLD"
            xattr -dr com.apple.quarantine "$OLD" 2>/dev/null
            tccutil reset Accessibility io.github.szyoo.cliptype >/dev/null 2>&1
            open "$OLD"
            # 作業ディレクトリ（zip・展開先・このスクリプト自身）を片付ける
            case "$WORK" in *cliptype-update-*) rm -rf "$WORK" ;; esac
            """
        do {
            // newApp は <work>/extract/Cliptype.app にある
            let workDir = newApp.deletingLastPathComponent().deletingLastPathComponent()
            let scriptURL = workDir.appendingPathComponent("install.sh")
            try script.write(to: scriptURL, atomically: true, encoding: .utf8)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = [
                scriptURL.path, String(ProcessInfo.processInfo.processIdentifier),
                current.path, newApp.path, workDir.path,
            ]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            NSApp.terminate(nil)
        } catch {
            status = .failed(error.localizedDescription)
            presentErrorAlert(error)
        }
    }

    private func run(_ tool: String, _ args: [String]) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try p.run()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { throw UpdateError.extractFailed }
    }

    // MARK: - ダイアログ

    private func presentUpdateAlert(_ release: Release) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = L("Cliptype %@ is available", release.version)
        let notes = String(release.notes.prefix(1200))
        alert.informativeText = L("You have %@. Release notes:\n\n%@", Self.currentVersion, notes)
        alert.addButton(withTitle: L("Download and Install"))
        alert.addButton(withTitle: L("Later"))
        alert.addButton(withTitle: L("Skip This Version"))
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            Task { @MainActor in await downloadAndPrepare(release) }
        case .alertThirdButtonReturn:
            UserDefaults.standard.set(release.version, forKey: "skippedUpdateVersion")
            status = .upToDate(Date())
        default:
            status = .upToDate(Date())
        }
    }

    private func presentReadyAlert(_ release: Release) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = L("Ready to install")
        alert.informativeText = L(
            "Cliptype will quit and relaunch as version %@. Because updates are not developer-signed yet, macOS will ask for the Accessibility permission again after the relaunch.",
            release.version
        )
        alert.addButton(withTitle: L("Install and Relaunch"))
        alert.addButton(withTitle: L("Cancel"))
        if alert.runModal() == .alertFirstButtonReturn {
            installAndRelaunch()
        } else {
            status = .available(release)
        }
    }

    private func presentUpToDateAlert() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = L("You're up to date")
        alert.informativeText = L("Cliptype %@ is the latest version.", Self.currentVersion)
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func presentErrorAlert(_ error: Error) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L("Update failed")
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    // MARK: - 表示用

    var statusDescription: String {
        switch status {
        case .idle: return ""
        case .checking: return L("Checking…")
        case .upToDate(let date):
            return L("Up to date (last checked %@)", date.formatted(date: .omitted, time: .shortened))
        case .available(let r): return L("Version %@ is available", r.version)
        case .downloading: return L("Downloading…")
        case .readyToInstall(let r): return L("Version %@ is ready to install", r.version)
        case .failed(let msg): return L("Update check failed: %@", msg)
        }
    }
}
