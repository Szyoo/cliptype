// Carbon RegisterEventHotKey の薄いラッパー。
// 複数のグローバルホットキーを id で登録し、押下を個別のコールバックで通知する
// （id 1 = クリップボード入力、id 2 = 履歴パネル）。

import Carbon.HIToolbox
import Foundation

final class HotkeyManager {
    private var handlerRef: EventHandlerRef?
    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var callbacks: [UInt32: () -> Void] = [:]

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

    /// `id` の既存登録を解除して、新しい組み合わせを登録する。
    func register(id: UInt32, keyCode: UInt32, modifiers: UInt32, onPressed: @escaping () -> Void) throws {
        unregister(id: id)
        try installHandlerIfNeeded()

        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x434C_5054) /* "CLPT" */, id: id)
        let status = RegisterEventHotKey(
            keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else { throw HotkeyError.register(status) }
        refs[id] = ref
        callbacks[id] = onPressed
    }

    func unregister(id: UInt32) {
        if let ref = refs.removeValue(forKey: id) {
            UnregisterEventHotKey(ref)
        }
        callbacks.removeValue(forKey: id)
    }

    private func installHandlerIfNeeded() throws {
        guard handlerRef == nil else { return }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let userData, let event else { return noErr }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                // どのホットキーが押されたかは EventHotKeyID から判別する
                var hotKeyID = EventHotKeyID()
                let err = GetEventParameter(
                    event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                    nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
                if err == noErr {
                    manager.callbacks[hotKeyID.id]?()
                }
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &handlerRef
        )
        guard status == noErr else { throw HotkeyError.installHandler(status) }
    }

    deinit {
        for ref in refs.values { UnregisterEventHotKey(ref) }
        if let ref = handlerRef { RemoveEventHandler(ref) }
    }
}
