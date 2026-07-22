// swift-tools-version: 5.9
// CliptypeApp — macOS ネイティブのメニューバー常駐アプリ。
// Rust の cliptype バイナリを入力エンジンとして .app に同梱する。
import PackageDescription

let package = Package(
    name: "CliptypeApp",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "CliptypeApp",
            path: "Sources/CliptypeApp"
        )
    ]
)
