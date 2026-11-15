import AppKit
import Carbon.HIToolbox
import ServiceManagement

/// Global shortcuts — change them here.
enum Shortcuts {
    /// ⌥⌘S — drag an area, or click a window
    static let area = Shortcut(
        keyCode: UInt32(kVK_ANSI_S),
        carbonModifiers: UInt32(cmdKey | optionKey),
        keyEquivalent: "s",
        modifierFlags: [.command, .option]
    )
    /// ⌥⌘F — the whole screen under the mouse
    static let fullScreen = Shortcut(
        keyCode: UInt32(kVK_ANSI_F),
        carbonModifiers: UInt32(cmdKey | optionKey),
        keyEquivalent: "f",
        modifierFlags: [.command, .option]
    )
}

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let capture = CaptureController()
    private var statusItem: NSStatusItem!
    private var hotKeys: [HotKey] = []
    private var clipboardOnlyItem: NSMenuItem!
    private var clipboardAndSaveItem: NSMenuItem!
    private var soundItem: NSMenuItem!
    private var loginItem: NSMenuItem!

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()
        register(Shortcuts.area) { [weak self] in self?.capture.startArea() }
        register(Shortcuts.fullScreen) { [weak self] in self?.capture.captureFullScreen() }
        if !CGPreflightScreenCaptureAccess() { CGRequestScreenCaptureAccess() }
    }

    private func register(_ shortcut: Shortcut, action: @escaping @MainActor () -> Void) {
        if let hotKey = HotKey(shortcut, action: action) {
            hotKeys.append(hotKey)
        } else {
            NSLog("Snap: couldn't register \(shortcut.display) — another app is probably using it")
        }
    }

    // MARK: Menu bar

    private func buildMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "Snap")
        statusItem.button?.image?.isTemplate = true

        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(item("Capture Area or Window", #selector(menuArea), shortcut: Shortcuts.area))
        menu.addItem(item("Capture Full Screen", #selector(menuFullScreen), shortcut: Shortcuts.fullScreen))
        menu.addItem(.separator())
        menu.addItem(.sectionHeader(title: "After Capture"))
        clipboardOnlyItem = item("Clipboard Only", #selector(useClipboardOnly))
        menu.addItem(clipboardOnlyItem)
        clipboardAndSaveItem = item("Clipboard & Save to Folder", #selector(useClipboardAndSave))
        menu.addItem(clipboardAndSaveItem)
        menu.addItem(item("Choose Folder…", #selector(chooseFolder)))
        menu.addItem(item("Open Folder", #selector(openFolder)))
        menu.addItem(.separator())
        soundItem = item("Play Sound", #selector(toggleSound))
        menu.addItem(soundItem)
        loginItem = item("Launch at Login", #selector(toggleLogin))
        menu.addItem(loginItem)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Snap", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)
        statusItem.menu = menu
    }

    private func item(_ title: String, _ action: Selector, shortcut: Shortcut? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: shortcut?.keyEquivalent ?? "")
        if let shortcut { item.keyEquivalentModifierMask = shortcut.modifierFlags }
        item.target = self
        return item
    }

    func menuWillOpen(_ menu: NSMenu) {
        clipboardOnlyItem.state = Settings.saveToFolder ? .off : .on
        clipboardAndSaveItem.state = Settings.saveToFolder ? .on : .off
        soundItem.state = Settings.playSound ? .on : .off
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    /// Give the menu a moment to fade out so it isn't in the frozen frame.
    @objc private func menuArea() {
        Task { try? await Task.sleep(for: .milliseconds(200)); capture.startArea() }
    }

    @objc private func menuFullScreen() {
        Task { try? await Task.sleep(for: .milliseconds(200)); capture.captureFullScreen() }
    }

    @objc private func useClipboardOnly() { Settings.saveToFolder = false }
    @objc private func useClipboardAndSave() { Settings.saveToFolder = true }
    @objc private func toggleSound() { Settings.playSound.toggle() }

    @objc private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Use Folder"
        panel.directoryURL = Settings.folder
        NSApp.activate()
        if panel.runModal() == .OK, let url = panel.url {
            Settings.folder = url
            Settings.saveToFolder = true
        }
    }

    @objc private func openFolder() {
        let folder = Settings.folder
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(folder)
    }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            let alert = NSAlert(error: error)
            NSApp.activate()
            alert.runModal()
        }
    }
}
