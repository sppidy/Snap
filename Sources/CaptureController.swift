import AppKit
import ScreenCaptureKit

@MainActor
final class CaptureController {
    private var overlays: [OverlayPanel] = []
    private var content: SCShareableContent?
    private var keyMonitor: Any?
    private var busy = false

    private var isActive: Bool { busy || !overlays.isEmpty }

    // MARK: Area / window

    /// Freezes every screen, then lets you drag an area or click a window.
    /// Pressing the shortcut again while selecting cancels.
    func startArea() {
        if !overlays.isEmpty { cancel(); return }
        guard !busy, hasPermission() else { return }
        busy = true
        let windows = Capture.windows()
        Task {
            defer { busy = false }
            do {
                let content = try await Capture.content()
                var frozen: [FrozenScreen] = []
                for screen in NSScreen.screens {
                    guard let display = Capture.display(for: screen, in: content) else { continue }
                    let image = try await Capture.image(of: display, in: content)
                    frozen.append(FrozenScreen(screen: screen, image: image))
                }
                guard !frozen.isEmpty else { return }
                self.content = content
                present(frozen, windows: windows)
            } catch {
                fail(error)
            }
        }
    }

    private func present(_ frozen: [FrozenScreen], windows: [WindowInfo]) {
        for screen in frozen {
            let panel = OverlayPanel.make(for: screen, windows: windows, controller: self)
            overlays.append(panel)
            panel.orderFrontRegardless()
        }
        let mouse = NSEvent.mouseLocation
        (overlays.first { NSMouseInRect(mouse, $0.frame, false) } ?? overlays.first)?.makeKey()
        NSCursor.crosshair.set()

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event } // Esc
            MainActor.assumeIsolated { self?.cancel() }
            return nil
        }
    }

    func finishArea(_ frozen: FrozenScreen, rect: NSRect, viewSize: NSSize) {
        end()
        guard let image = crop(frozen, rect: rect, viewSize: viewSize) else { NSSound.beep(); return }
        Output.deliver(image, scale: CGFloat(frozen.image.width) / viewSize.width, screen: frozen.screen)
    }

    func finishWindow(_ window: WindowInfo, frozen: FrozenScreen, visibleRect: NSRect, viewSize: NSSize) {
        let content = self.content
        end()
        Task {
            do {
                guard let content else { throw CaptureError.windowGone }
                let image = try await Capture.image(ofWindow: window.id, in: content)
                Output.deliver(image, scale: CGFloat(image.width) / window.frame.width, screen: frozen.screen)
            } catch {
                // Fall back to what was visible on the frozen screen.
                guard let image = crop(frozen, rect: visibleRect, viewSize: viewSize) else { fail(error); return }
                Output.deliver(image, scale: CGFloat(frozen.image.width) / viewSize.width, screen: frozen.screen)
            }
        }
    }

    func cancel() { end() }

    private func end() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        overlays.forEach { $0.orderOut(nil) }
        overlays.removeAll()
        content = nil
    }

    private func crop(_ frozen: FrozenScreen, rect: NSRect, viewSize: NSSize) -> CGImage? {
        let sx = CGFloat(frozen.image.width) / viewSize.width
        let sy = CGFloat(frozen.image.height) / viewSize.height
        let pixels = CGRect(
            x: rect.minX * sx,
            y: (viewSize.height - rect.maxY) * sy, // AppKit is bottom-up, CGImage is top-down
            width: rect.width * sx,
            height: rect.height * sy
        ).integral
        return frozen.image.cropping(to: pixels)
    }

    // MARK: Full screen

    /// Captures the display the mouse is on.
    func captureFullScreen() {
        guard !isActive, hasPermission() else { return }
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main
        else { return }
        busy = true
        Task {
            defer { busy = false }
            do {
                let content = try await Capture.content()
                guard let display = Capture.display(for: screen, in: content) else { return }
                let image = try await Capture.image(of: display, in: content)
                Output.deliver(image, scale: CGFloat(image.width) / screen.frame.width, screen: screen)
            } catch {
                fail(error)
            }
        }
    }

    // MARK: Helpers

    private func hasPermission() -> Bool {
        if CGPreflightScreenCaptureAccess() { return true }
        let alert = NSAlert()
        alert.messageText = "Snap needs Screen Recording access"
        alert.informativeText = "Turn on Snap in System Settings → Privacy & Security → Screen & System Audio Recording, then quit and reopen Snap."
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
        return false
    }

    private func fail(_ error: Error) {
        NSLog("Snap: capture failed: \(error.localizedDescription)")
        NSSound.beep()
    }
}
