import AppKit
import ScreenCaptureKit

extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
}

/// A screen plus a frozen image of it, taken right before the selection overlay appears.
struct FrozenScreen {
    let screen: NSScreen
    let image: CGImage
}

/// An on-screen app window. `frame` is in global Quartz coordinates (top-left origin).
struct WindowInfo {
    let id: CGWindowID
    let frame: CGRect
}

enum CaptureError: LocalizedError {
    case windowGone
    var errorDescription: String? { "The window is no longer available." }
}

enum Capture {
    static func content() async throws -> SCShareableContent {
        try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
    }

    static func display(for screen: NSScreen, in content: SCShareableContent) -> SCDisplay? {
        content.displays.first { $0.displayID == screen.displayID }
    }

    /// Whole display, with Snap's own windows (thumbnail, menu bar icon) left out.
    static func image(of display: SCDisplay, in content: SCShareableContent) async throws -> CGImage {
        let pid = ProcessInfo.processInfo.processIdentifier
        let me = content.applications.filter { $0.processID == pid }
        let filter = SCContentFilter(display: display, excludingApplications: me, exceptingWindows: [])
        return try await shoot(filter)
    }

    /// A single window on its own — nothing overlapping it, no shadow.
    static func image(ofWindow id: CGWindowID, in content: SCShareableContent) async throws -> CGImage {
        guard let window = content.windows.first(where: { $0.windowID == id }) else {
            throw CaptureError.windowGone
        }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        return try await shoot(filter) { $0.ignoreShadowsSingleWindow = true }
    }

    private static func shoot(
        _ filter: SCContentFilter,
        configure: (SCStreamConfiguration) -> Void = { _ in }
    ) async throws -> CGImage {
        let config = SCStreamConfiguration()
        let scale = CGFloat(filter.pointPixelScale)
        config.width = Int((filter.contentRect.width * scale).rounded())
        config.height = Int((filter.contentRect.height * scale).rounded())
        config.showsCursor = false
        config.captureResolution = .best
        configure(config)
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }

    /// Normal app windows currently on screen, frontmost first.
    static func windows() -> [WindowInfo] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        let pid = ProcessInfo.processInfo.processIdentifier
        return list.compactMap { info in
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  (info[kCGWindowOwnerPID as String] as? pid_t) != pid,
                  let id = info[kCGWindowNumber as String] as? CGWindowID,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                  frame.width >= 40, frame.height >= 40
            else { return nil }
            if let alpha = info[kCGWindowAlpha as String] as? Double, alpha < 0.05 { return nil }
            return WindowInfo(id: id, frame: frame)
        }
    }
}
