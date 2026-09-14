// クリップボード履歴のフローティングパネル。
//
// ホットキーで呼び出し、1〜9 / ↑↓ + Return で項目を選ぶと、パネルを閉じてから
// 同梱エンジン（--stdin）で直接キー入力する。⌘Return はクリップボードへ戻すだけ。
//
// 焦点を奪わないことが肝: NSPanel を `.nonactivatingPanel` で作り、NSApp.activate は
// 呼ばない。パネルは key window になってキー入力を受け取れるが、アプリ自体は
// アクティブにならないので、対象アプリの入力欄のフォーカスはそのまま残る
// （Maccy / Alfred / Raycast と同じ手法）。
//
// 表示位置は設定で選ぶ: ステータスバーアイコンの下（既定）/ テキストカーソル付近
// （取れないときはアイコン下へ退避）/ 画面中央 / ユーザーがドラッグして決めた位置。

import AppKit
import ApplicationServices
import SwiftUI

/// パネルの表示位置。
enum PanelPosition: String, CaseIterable {
    /// ステータスバーの自アイコンの直下（既定）
    case statusItem
    /// 対象アプリのテキストカーソル付近（AX で取得。取れなければ statusItem）
    case caret
    /// 画面中央（少し上）
    case center
    /// ユーザーがドラッグして決めた位置
    case custom

    static var current: PanelPosition {
        get { PanelPosition(rawValue: UserDefaults.standard.string(forKey: "panelPosition") ?? "") ?? .statusItem }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "panelPosition") }
    }
}

/// パネル内の状態（検索語・選択行）。SwiftUI ビューが購読する。
@MainActor
final class HistoryPanelModel: ObservableObject {
    @Published var query = ""
    @Published var selectedIndex = 0

    var filtered: [ClipEntry] {
        let all = ClipboardHistory.shared.entries
        let q = query.trimmingCharacters(in: .whitespaces)
        if q.isEmpty { return all }
        return all.filter { $0.text.localizedCaseInsensitiveContains(q) }
    }
}

/// フォーカスを奪わないパネル。
final class HistoryPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class HistoryPanelController: NSObject, NSWindowDelegate {
    static let shared = HistoryPanelController()

    static let panelWidth: CGFloat = 440
    static let panelHeight: CGFloat = 380

    let model = HistoryPanelModel()
    private var panel: HistoryPanel?
    private var keyMonitor: Any?
    private var didMoveObserver: NSObjectProtocol?
    /// show() で自分が位置決めした直後の didMove を「ユーザーのドラッグ」と誤認しないための時刻
    private var shownAt = Date.distantPast

    var isVisible: Bool { panel?.isVisible ?? false }

    // MARK: - 表示 / 非表示

    func toggle() {
        if isVisible { hide() } else { show() }
    }

    func show() {
        let panel = panel ?? makePanel()
        self.panel = panel
        model.query = ""
        model.selectedIndex = 0

        panel.isMovableByWindowBackground = (PanelPosition.current == .custom)
        shownAt = Date()
        panel.setFrameOrigin(originFor(PanelPosition.current, size: panel.frame.size))
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            panel.animator().alphaValue = 1
        }
        installKeyMonitor()
    }

    func hide() {
        guard let panel, panel.isVisible else { return }
        removeKeyMonitor()
        panel.orderOut(nil)
    }

    /// 選択した項目を確定する。`copyOnly` ならクリップボードへ戻すだけ。
    func confirm(index: Int, copyOnly: Bool = false) {
        let items = model.filtered
        guard items.indices.contains(index) else { return }
        let entry = items[index]
        hide()
        if copyOnly {
            ClipboardHistory.shared.copyToPasteboard(entry)
            return
        }
        // パネルが消えて対象アプリにキーが戻るのを少し待ってから入力する
        let interval = AppState.shared.intervalMs
        let keycode = AppState.shared.keycodeMode
        Task.detached(priority: .userInitiated) {
            try? await Task.sleep(for: .milliseconds(120))
            await Engine.typeText(entry.text, intervalMs: interval, keycodeMode: keycode)
        }
    }

    /// カスタム位置を忘れて既定位置へ戻す。
    func resetCustomPosition() {
        UserDefaults.standard.removeObject(forKey: "panelCustomOrigin")
    }

    // MARK: - パネル生成

    private func makePanel() -> HistoryPanel {
        let size = NSSize(width: Self.panelWidth, height: Self.panelHeight)
        let panel = HistoryPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isReleasedWhenClosed = false
        panel.delegate = self

        let host = NSHostingView(rootView: HistoryPanelView(model: model, controller: self))
        host.frame = NSRect(origin: .zero, size: size)
        panel.contentView = host

        // カスタム位置: ドラッグして離した位置を保存する
        didMoveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification, object: panel, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.savePositionIfCustom() }
        }
        return panel
    }

    private func savePositionIfCustom() {
        guard PanelPosition.current == .custom, let panel, panel.isVisible else { return }
        // 表示直後 0.5 秒以内の移動はプログラムによる位置決めなので保存しない
        guard Date().timeIntervalSince(shownAt) > 0.5 else { return }
        let o = panel.frame.origin
        UserDefaults.standard.set("\(o.x),\(o.y)", forKey: "panelCustomOrigin")
    }

    // MARK: - キー操作

    private func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let panel = self.panel, event.window === panel else { return event }
            return self.handleKey(event) ? nil : event
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    /// 処理したら true（イベントを飲み込む）。false なら検索欄へ流す。
    private func handleKey(_ event: NSEvent) -> Bool {
        let cmd = event.modifierFlags.contains(.command)
        switch event.keyCode {
        case 53: // Esc
            hide()
            return true
        case 36, 76: // Return / Enter
            confirm(index: model.selectedIndex, copyOnly: cmd)
            return true
        case 125: // ↓
            moveSelection(1)
            return true
        case 126: // ↑
            moveSelection(-1)
            return true
        default:
            break
        }
        // 数字キー: 検索語が空のとき（または ⌘ 付き）は 1〜9 で直接選択
        if let ch = event.charactersIgnoringModifiers, ch.count == 1,
            let digit = Int(ch), (1...9).contains(digit),
            model.query.isEmpty || cmd
        {
            confirm(index: digit - 1)
            return true
        }
        return false
    }

    private func moveSelection(_ delta: Int) {
        let count = model.filtered.count
        guard count > 0 else { return }
        model.selectedIndex = (model.selectedIndex + delta + count) % count
    }

    // MARK: - NSWindowDelegate

    func windowDidResignKey(_ notification: Notification) {
        // 他をクリックしたら閉じる（Spotlight 等と同じ挙動）
        hide()
    }

    // MARK: - 位置決め

    private func originFor(_ position: PanelPosition, size: NSSize) -> NSPoint {
        switch position {
        case .statusItem:
            return belowStatusItem(size: size)
        case .caret:
            if let rect = Self.caretScreenRect() {
                return nearCaret(rect, size: size)
            }
            return belowStatusItem(size: size)
        case .center:
            let screen = Self.screenUnderMouse()
            let vf = screen.visibleFrame
            return clamp(
                NSPoint(x: vf.midX - size.width / 2, y: vf.midY - size.height / 2 + vf.height * 0.12),
                size: size, in: screen)
        case .custom:
            if let saved = UserDefaults.standard.string(forKey: "panelCustomOrigin") {
                let parts = saved.split(separator: ",").compactMap { Double($0) }
                if parts.count == 2 {
                    let p = NSPoint(x: parts[0], y: parts[1])
                    let screen = NSScreen.screens.first { $0.frame.contains(p) } ?? Self.screenUnderMouse()
                    return clamp(p, size: size, in: screen)
                }
            }
            return belowStatusItem(size: size)
        }
    }

    /// ステータスバーの自アイコンの直下、水平中央揃え。アイコンが見つからない
    /// （メニューバーの溢れで隠れている等）ときはマウスのある画面の上部中央。
    private func belowStatusItem(size: NSSize) -> NSPoint {
        if let itemFrame = Self.statusItemFrame() {
            let screen = NSScreen.screens.first { $0.frame.intersects(itemFrame) } ?? Self.screenUnderMouse()
            let p = NSPoint(x: itemFrame.midX - size.width / 2, y: itemFrame.minY - 6 - size.height)
            return clamp(p, size: size, in: screen)
        }
        let screen = Self.screenUnderMouse()
        let vf = screen.visibleFrame
        return clamp(NSPoint(x: vf.midX - size.width / 2, y: vf.maxY - 6 - size.height), size: size, in: screen)
    }

    /// カーソル行の下に出す。下に入らなければ上に出す。
    private func nearCaret(_ caret: NSRect, size: NSSize) -> NSPoint {
        let screen = NSScreen.screens.first { $0.frame.intersects(caret) } ?? Self.screenUnderMouse()
        var p = NSPoint(x: caret.minX, y: caret.minY - 8 - size.height)
        if p.y < screen.visibleFrame.minY {
            p.y = caret.maxY + 8
        }
        return clamp(p, size: size, in: screen)
    }

    private func clamp(_ p: NSPoint, size: NSSize, in screen: NSScreen) -> NSPoint {
        let vf = screen.visibleFrame
        let x = min(max(p.x, vf.minX + 8), vf.maxX - size.width - 8)
        let y = min(max(p.y, vf.minY + 8), vf.maxY - size.height - 8)
        return NSPoint(x: x, y: y)
    }

    /// MenuBarExtra のアイコンは自プロセス内の NSStatusBarWindow に載っている。
    private static func statusItemFrame() -> NSRect? {
        NSApp.windows.first { String(describing: type(of: $0)).contains("StatusBarWindow") }?.frame
    }

    private static func screenUnderMouse() -> NSScreen {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    /// 対象アプリのテキストカーソル位置（AppKit 座標）。取れなければ nil。
    /// AX の座標は左上原点なので、メインスクリーン高さで反転する。
    static func caretScreenRect() -> NSRect? {
        let system = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
            let focusedAny = focusedRef
        else { return nil }
        let focused = unsafeBitCast(focusedAny, to: AXUIElement.self)

        var rangeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(focused, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
            let range = rangeRef
        else { return nil }

        var boundsRef: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            focused, kAXBoundsForRangeParameterizedAttribute as CFString, range, &boundsRef) == .success,
            let boundsAny = boundsRef
        else { return nil }
        var rect = CGRect.zero
        guard AXValueGetValue(unsafeBitCast(boundsAny, to: AXValue.self), .cgRect, &rect),
            rect.origin != .zero || rect.size != .zero
        else { return nil }

        guard let primary = NSScreen.screens.first else { return nil }
        let flippedY = primary.frame.maxY - rect.maxY
        return NSRect(x: rect.minX, y: flippedY, width: max(rect.width, 1), height: max(rect.height, 1))
    }
}
