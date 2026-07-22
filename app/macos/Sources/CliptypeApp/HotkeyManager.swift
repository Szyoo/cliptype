// Carbon RegisterEventHotKey の薄いラッパー。
// グローバルホットキーの押下を onPressed コールバックで通知する。

import Carbon.HIToolbox
import Foundation

final class HotkeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    /// ホットキー押下時に呼ばれる（Carbon のイベントスレッド = メインスレッド）。
    var onPressed: (() -> Void)?

    enum HotkeyError: LocalizedError {
        case installHandler(OSStatus)
        case register(OSStatus)

        var errorDescription: String? {
            switch self {
            case .installHandler(let s): return "InstallEventHandler failed (\(s))"
            case .register(let s): return "RegisterEventHotKey failed (\(s)) — combo already in use?"
            }
        }
    }

    /// 既存の登録を解除して、新しい組み合わせを登録する。
    func register(keyCode: UInt32, modifiers: UInt32) throws {
        unregister()

        if handlerRef == nil {
            var eventType = EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyPressed)
            )
            let status = InstallEventHandler(
                GetApplicationEventTarget(),
                { _, _, userData in
                    guard let userData else { return noErr }
                    let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                    manager.onPressed?()
                    return noErr
                },
                1,
                &eventType,
                Unmanaged.passUnretained(self).toOpaque(),
                &handlerRef
            )
            guard status == noErr else { throw HotkeyError.installHandler(status) }
        }

        let hotKeyID = EventHotKeyID(signature: OSType(0x434C_5054) /* "CLPT" */, id: 1)
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        guard status == noErr else { throw HotkeyError.register(status) }
    }

    func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
    }

    deinit {
        unregister()
        if let ref = handlerRef {
            RemoveEventHandler(ref)
        }
    }
}
