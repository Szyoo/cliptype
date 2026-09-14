// キーの組み合わせ（Carbon 仮想キーコード + 修飾キー）。
// ホットキーはプリセットではなくユーザーが自由に録音して決める。
// 表示用ラベル（⌃⌥⇧⌘ + キー名）は現在のキーボード配列から作る。

import AppKit
import Carbon.HIToolbox

struct KeyCombo: Equatable {
    /// Carbon 仮想キーコード（例: V = 9, H = 4）
    let keyCode: UInt32
    /// Carbon 修飾キーフラグ（controlKey / optionKey / shiftKey / cmdKey の組み合わせ）
    let modifiers: UInt32

    static let defaultType = KeyCombo(keyCode: 9, modifiers: UInt32(controlKey | shiftKey))   // ⌃⇧V
    static let defaultPanel = KeyCombo(keyCode: 4, modifiers: UInt32(controlKey | shiftKey))  // ⌃⇧H

    // MARK: - 永続化（"keyCode:modifiers"）

    var storageString: String { "\(keyCode):\(modifiers)" }

    init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    init?(storageString: String) {
        let parts = storageString.split(separator: ":")
        guard parts.count == 2, let k = UInt32(parts[0]), let m = UInt32(parts[1]) else { return nil }
        self.init(keyCode: k, modifiers: m)
    }

    /// 旧バージョンのプリセット id からの移行。
    init?(legacyPresetID: String) {
        switch legacyPresetID {
        case "ctrl-shift-v": self.init(keyCode: 9, modifiers: UInt32(controlKey | shiftKey))
        case "ctrl-opt-v": self.init(keyCode: 9, modifiers: UInt32(controlKey | optionKey))
        case "cmd-shift-b": self.init(keyCode: 11, modifiers: UInt32(cmdKey | shiftKey))
        case "ctrl-shift-p": self.init(keyCode: 35, modifiers: UInt32(controlKey | shiftKey))
        case "ctrl-shift-h": self.init(keyCode: 4, modifiers: UInt32(controlKey | shiftKey))
        case "ctrl-opt-h": self.init(keyCode: 4, modifiers: UInt32(controlKey | optionKey))
        case "cmd-shift-h": self.init(keyCode: 4, modifiers: UInt32(cmdKey | shiftKey))
        default: return nil
        }
    }

    // MARK: - NSEvent から

    /// キー押下イベントから組み合わせを作る。修飾キーが 1 つも無ければ nil
    /// （グローバルホットキーとしては使えない）。
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var mods: UInt32 = 0
        if flags.contains(.control) { mods |= UInt32(controlKey) }
        if flags.contains(.option) { mods |= UInt32(optionKey) }
        if flags.contains(.shift) { mods |= UInt32(shiftKey) }
        if flags.contains(.command) { mods |= UInt32(cmdKey) }
        guard mods != 0 else { return nil }
        // 修飾キー単独の押下（keyCode が修飾キー自身）は除外
        let modifierKeyCodes: Set<UInt16> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]
        guard !modifierKeyCodes.contains(event.keyCode) else { return nil }
        self.init(keyCode: UInt32(event.keyCode), modifiers: mods)
    }

    // MARK: - 表示

    /// "⌃⇧V" のようなラベル（修飾キーは macOS 標準の並び ⌃⌥⇧⌘）。
    var label: String {
        var s = ""
        if modifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { s += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { s += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { s += "⌘" }
        return s + Self.keyName(for: keyCode)
    }

    /// キーコードの表示名。特殊キーは記号、それ以外は現在の配列で翻訳した文字。
    static func keyName(for keyCode: UInt32) -> String {
        let special: [UInt32: String] = [
            36: "↩", 76: "⌤", 48: "⇥", 49: "Space", 51: "⌫", 117: "⌦", 53: "⎋",
            123: "←", 124: "→", 125: "↓", 126: "↑", 115: "↖", 119: "↘", 116: "⇞", 121: "⇟",
            122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
            101: "F9", 109: "F10", 103: "F11", 111: "F12", 105: "F13", 107: "F14", 113: "F15",
            106: "F16", 64: "F17", 79: "F18", 80: "F19", 90: "F20",
        ]
        if let name = special[keyCode] { return name }
        if let ch = translate(keyCode: keyCode) { return ch.uppercased() }
        return "key\(keyCode)"
    }

    /// 現在のキーボード配列で keyCode（修飾なし）が生む文字。
    private static func translate(keyCode: UInt32) -> String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
            let dataRef = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }
        let data = unsafeBitCast(dataRef, to: CFData.self) as Data
        var deadKeyState: UInt32 = 0
        var length = 0
        var chars = [UniChar](repeating: 0, count: 4)
        let status = data.withUnsafeBytes { buf -> OSStatus in
            guard let layout = buf.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else {
                return OSStatus(paramErr)
            }
            return UCKeyTranslate(
                layout, UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0,
                UInt32(LMGetKbdType()), UInt32(kUCKeyTranslateNoDeadKeysMask),
                &deadKeyState, chars.count, &length, &chars)
        }
        guard status == noErr, length > 0 else { return nil }
        let s = String(utf16CodeUnits: chars, count: length)
        return s.trimmingCharacters(in: .controlCharacters).isEmpty ? nil : s
    }
}
