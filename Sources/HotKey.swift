import AppKit
import Carbon.HIToolbox

/// A global keyboard shortcut. `keyCode` is a Carbon virtual key code (kVK_*).
struct Shortcut {
    let keyCode: UInt32
    let carbonModifiers: UInt32
    let keyEquivalent: String
    let modifierFlags: NSEvent.ModifierFlags

    var display: String {
        var s = ""
        if modifierFlags.contains(.control) { s += "⌃" }
        if modifierFlags.contains(.option) { s += "⌥" }
        if modifierFlags.contains(.shift) { s += "⇧" }
        if modifierFlags.contains(.command) { s += "⌘" }
        return s + keyEquivalent.uppercased()
    }
}

/// System-wide hotkey via Carbon's RegisterEventHotKey.
/// Needs no Accessibility permission and swallows the keystroke.
@MainActor
final class HotKey {
    private static var actions: [UInt32: @MainActor () -> Void] = [:]
    private static var nextID: UInt32 = 1
    private static var handlerInstalled = false

    private var ref: EventHotKeyRef?

    init?(_ shortcut: Shortcut, action: @escaping @MainActor () -> Void) {
        HotKey.installHandler()
        let id = HotKey.nextID
        HotKey.nextID += 1
        let hotKeyID = EventHotKeyID(signature: 0x534E_4150 /* 'SNAP' */, id: id)
        let status = RegisterEventHotKey(
            shortcut.keyCode, shortcut.carbonModifiers, hotKeyID,
            GetApplicationEventTarget(), 0, &ref
        )
        guard status == noErr else { return nil }
        HotKey.actions[id] = action
    }

    private static func installHandler() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(GetApplicationEventTarget(), hotKeyHandler, 1, &spec, nil, nil)
    }

    fileprivate static func fire(_ id: UInt32) {
        actions[id]?()
    }
}

private func hotKeyHandler(
    _ call: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event else { return OSStatus(eventNotHandledErr) }
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard status == noErr else { return status }
    let id = hotKeyID.id
    Task { @MainActor in HotKey.fire(id) }
    return noErr
}
