import Carbon.HIToolbox.Events
import Cocoa

// MARK: - Global Shortcut Manager

/// Manages global keyboard shortcuts using Carbon APIs for the floating control bar.
class GlobalShortcutManager {
    static let shared = GlobalShortcutManager()

    static let toggleFloatingBarNotification = Notification.Name("com.fazm.desktop.toggleFloatingBar")
    static let askAINotification = Notification.Name("com.fazm.desktop.askAI")

    private var hotKeyRefs: [HotKeyID: EventHotKeyRef] = [:]

    private enum HotKeyID: UInt32 {
        case toggleBar = 1
        case askFazm = 2
    }

    private var shortcutObserver: NSObjectProtocol?

    private init() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: OSType(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, event, _) -> OSStatus in
                return GlobalShortcutManager.shared.handleHotKeyEvent(event!)
            },
            1, &eventType, nil, nil
        )

        // Re-register Ask Fazm shortcut when user changes it in settings
        shortcutObserver = NotificationCenter.default.addObserver(
            forName: ShortcutSettings.askFazmShortcutChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.registerAskFazm()
        }
    }

    func registerShortcuts() {
        unregisterShortcuts()
        // Register Cmd+\ for toggle bar (keycode 42 = backslash)
        registerHotKey(keyCode: 42, modifiers: Int(cmdKey), id: .toggleBar)
        // Register Ask Fazm shortcut from user settings
        registerAskFazm()
    }

    private func registerAskFazm() {
        // Unregister previous Ask Fazm hotkey if any
        if let ref = hotKeyRefs.removeValue(forKey: .askFazm) {
            UnregisterEventHotKey(ref)
        }
        let askFazmKey = MainActor.assumeIsolated { ShortcutSettings.shared.askFazmKey }
        registerHotKey(keyCode: Int(askFazmKey.keyCode), modifiers: askFazmKey.carbonModifiers, id: .askFazm)
        NSLog("GlobalShortcutManager: Registered Ask Fazm shortcut: \(askFazmKey.rawValue)")
    }

    private func registerHotKey(keyCode: Int, modifiers: Int, id: HotKeyID) {
        var hotKeyRef: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: FourCharCode(0x46415A4D), id: id.rawValue) // "FAZM"

        let status = RegisterEventHotKey(
            UInt32(keyCode), UInt32(modifiers), hotKeyID,
            GetApplicationEventTarget(), 0, &hotKeyRef
        )

        if status == noErr, let ref = hotKeyRef {
            hotKeyRefs[id] = ref
        } else {
            NSLog("GlobalShortcutManager: Failed to register hotkey (keycode \(keyCode)), error: \(status)")
        }
    }

    private func handleHotKeyEvent(_ event: EventRef) -> OSStatus {
        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            OSType(kEventParamDirectObject),
            OSType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )

        guard status == noErr, let id = HotKeyID(rawValue: hotKeyID.id) else {
            return status
        }

        switch id {
        case .toggleBar:
            NSLog("GlobalShortcutManager: Cmd+\\ detected, toggling floating bar")
            NotificationCenter.default.post(name: GlobalShortcutManager.toggleFloatingBarNotification, object: nil)
        case .askFazm:
            NSLog("GlobalShortcutManager: Ask Fazm shortcut detected")
            DispatchQueue.main.async {
                FloatingControlBarManager.shared.openAIInput()
            }
        }

        return noErr
    }

    func unregisterShortcuts() {
        for (_, ref) in hotKeyRefs {
            UnregisterEventHotKey(ref)
        }
        hotKeyRefs.removeAll()
    }
}
