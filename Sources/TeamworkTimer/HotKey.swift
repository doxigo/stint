import Carbon.HIToolbox

/// One system-wide shortcut for Start/Pause, via Carbon hot keys (no Accessibility permission needed).
/// Off by default so it never steals a combination another app uses.
// ponytail: preset combinations; add a recorder if someone needs a custom one
@MainActor
enum HotKey {
    enum Preset: String, CaseIterable, Identifiable {
        case none = "None"
        case controlOptionCommandT = "⌃⌥⌘T"
        case controlOptionCommandP = "⌃⌥⌘P"
        case controlOptionSpace = "⌃⌥Space"
        var id: Self { self }

        fileprivate var key: (code: Int, modifiers: Int)? {
            switch self {
            case .none: nil
            case .controlOptionCommandT: (kVK_ANSI_T, controlKey | optionKey | cmdKey)
            case .controlOptionCommandP: (kVK_ANSI_P, controlKey | optionKey | cmdKey)
            case .controlOptionSpace: (kVK_Space, controlKey | optionKey)
            }
        }
    }

    static var saved: Preset { Preset(rawValue: UserDefaults.standard.string(forKey: "globalShortcut") ?? "") ?? .none }

    private static var action: (() -> Void)?
    private static var registered: EventHotKeyRef?
    private static var handlerInstalled = false

    /// Registers `preset` (replacing any previous one); `action` runs on each press.
    /// Returns false when another app already owns the combination.
    @discardableResult
    static func apply(_ preset: Preset, action: @escaping () -> Void) -> Bool {
        self.action = action
        if let registered { UnregisterEventHotKey(registered) }
        registered = nil
        guard let key = preset.key else { return true }

        if !handlerInstalled {
            var pressed = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
                Task { @MainActor in HotKey.action?() }
                return noErr
            }, 1, &pressed, nil, nil)
            handlerInstalled = true
        }
        let id = EventHotKeyID(signature: OSType(0x5457_5449), id: 1) // "TWTI"
        return RegisterEventHotKey(UInt32(key.code), UInt32(key.modifiers), id, GetApplicationEventTarget(), 0, &registered) == noErr
    }
}
