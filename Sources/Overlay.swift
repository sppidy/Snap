import AppKit
import QuartzCore

/// Full-screen, borderless panel that shows the frozen screen.
/// Non-activating, so the app you were in keeps focus.
final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }

    static func make(for frozen: FrozenScreen, windows: [WindowInfo], controller: CaptureController) -> OverlayPanel {
        let frame = frozen.screen.frame
        let panel = OverlayPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.setFrame(frame, display: false)
        panel.level = .screenSaver
        panel.isOpaque = true
        panel.backgroundColor = .black
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.acceptsMouseMovedEvents = true
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.contentView = OverlayView(
            frame: NSRect(origin: .zero, size: frame.size),
            frozen: frozen,
            windows: windows,
            controller: controller
        )
        return panel
    }
}

/// Hover a window to highlight it, click to grab it. Drag to grab an area.
final class OverlayView: NSView {
    private let frozen: FrozenScreen
    private let targets: [(info: WindowInfo, rect: NSRect)] // rect: visible part, in view coords
    private weak var controller: CaptureController?

    private let dim = CAShapeLayer()
    private let border = CAShapeLayer()
    private let badge = CALayer()
    private let badgeText = CATextLayer()
    private let badgeFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)

    private var dragOrigin: NSPoint?
    private var selection: NSRect?
    private var hovered: Int?

    init(frame: NSRect, frozen: FrozenScreen, windows: [WindowInfo], controller: CaptureController) {
        self.frozen = frozen
        self.controller = controller

        let screenFrame = frozen.screen.frame
        let primaryHeight = NSScreen.screens.first?.frame.height ?? screenFrame.height
        let bounds = NSRect(origin: .zero, size: frame.size)
        self.targets = windows.compactMap { window in
            let global = NSRect(
                x: window.frame.minX,
                y: primaryHeight - window.frame.maxY,
                width: window.frame.width,
                height: window.frame.height
            )
            let local = global.offsetBy(dx: -screenFrame.minX, dy: -screenFrame.minY)
            let visible = local.intersection(bounds)
            return visible.isEmpty ? nil : (info: window, rect: visible)
        }

        super.init(frame: frame)
        setupLayers()
        hovered = hitWindow(at: localMouse())
        refresh()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private var pixelScale: CGFloat { CGFloat(frozen.image.width) / bounds.width }

    // MARK: Layers

    private func setupLayers() {
        let root = CALayer()
        root.frame = bounds
        root.contents = frozen.image
        root.contentsGravity = .resize
        layer = root
        wantsLayer = true

        let scale = frozen.screen.backingScaleFactor

        dim.frame = bounds
        dim.contentsScale = scale
        dim.fillRule = .evenOdd
        dim.fillColor = NSColor.black.withAlphaComponent(0.35).cgColor

        border.frame = bounds
        border.contentsScale = scale
        border.lineWidth = 1.5

        badge.backgroundColor = NSColor.black.withAlphaComponent(0.75).cgColor
        badge.cornerRadius = 5
        badge.isHidden = true
        badgeText.contentsScale = scale
        badgeText.font = badgeFont
        badgeText.fontSize = badgeFont.pointSize
        badgeText.foregroundColor = NSColor.white.cgColor
        badgeText.alignmentMode = .center
        badge.addSublayer(badgeText)

        [dim, border, badge].forEach(root.addSublayer)
    }

    private func refresh() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        let path = CGMutablePath()
        path.addRect(bounds)

        guard let hole = selection ?? hovered.map({ targets[$0].rect }) else {
            dim.path = path
            border.path = nil
            badge.isHidden = true
            return
        }

        path.addRect(hole)
        dim.path = path
        border.path = CGPath(rect: hole.insetBy(dx: 0.75, dy: 0.75), transform: nil)
        if selection != nil {
            border.strokeColor = NSColor.white.cgColor
            border.fillColor = nil
        } else {
            border.strokeColor = NSColor.controlAccentColor.cgColor
            border.fillColor = NSColor.controlAccentColor.withAlphaComponent(0.12).cgColor
        }

        let text = "\(Int((hole.width * pixelScale).rounded())) × \(Int((hole.height * pixelScale).rounded()))"
        badgeText.string = text
        let size = (text as NSString).size(withAttributes: [.font: badgeFont])
        let w = ceil(size.width) + 14
        let h = ceil(size.height) + 6
        var origin = NSPoint(x: hole.minX, y: hole.minY - h - 6)
        if origin.y < 4 { origin = NSPoint(x: hole.minX + 6, y: hole.minY + 6) } // no room below: tuck inside
        origin.x = min(max(origin.x, 4), bounds.width - w - 4)
        badge.frame = CGRect(origin: origin, size: CGSize(width: w, height: h))
        badgeText.frame = CGRect(x: 0, y: (h - ceil(size.height)) / 2 - 0.5, width: w, height: ceil(size.height))
        badge.isHidden = false
    }

    // MARK: Mouse

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .cursorUpdate, .activeAlways, .inVisibleRect],
            owner: self
        ))
    }

    override func cursorUpdate(with event: NSEvent) { NSCursor.crosshair.set() }

    override func mouseEntered(with event: NSEvent) {
        window?.makeKey()
        NSCursor.crosshair.set()
    }

    override func mouseExited(with event: NSEvent) {
        guard dragOrigin == nil, hovered != nil else { return }
        hovered = nil
        refresh()
    }

    override func mouseMoved(with event: NSEvent) {
        NSCursor.crosshair.set()
        guard dragOrigin == nil else { return }
        let hit = hitWindow(at: localMouse())
        if hit != hovered {
            hovered = hit
            refresh()
        }
    }

    override func mouseDown(with event: NSEvent) {
        dragOrigin = clamp(localMouse())
        selection = nil
    }

    override func mouseDragged(with event: NSEvent) {
        guard let origin = dragOrigin else { return }
        let p = clamp(localMouse())
        if selection == nil, hypot(p.x - origin.x, p.y - origin.y) < 4 { return } // still a click
        selection = NSRect(
            x: min(origin.x, p.x), y: min(origin.y, p.y),
            width: abs(p.x - origin.x), height: abs(p.y - origin.y)
        )
        refresh()
    }

    override func mouseUp(with event: NSEvent) {
        defer { dragOrigin = nil }
        if let selection {
            if selection.width >= 4, selection.height >= 4 {
                controller?.finishArea(frozen, rect: selection, viewSize: bounds.size)
            } else {
                self.selection = nil
                hovered = hitWindow(at: localMouse())
                refresh()
            }
        } else if let hovered {
            let target = targets[hovered]
            controller?.finishWindow(target.info, frozen: frozen, visibleRect: target.rect, viewSize: bounds.size)
        }
    }

    override func rightMouseDown(with event: NSEvent) { controller?.cancel() }

    // MARK: Geometry

    /// Mouse position in this view, read from the global location so it works
    /// on every screen regardless of which overlay is key.
    private func localMouse() -> NSPoint {
        let m = NSEvent.mouseLocation
        let f = frozen.screen.frame
        return NSPoint(x: m.x - f.minX, y: m.y - f.minY)
    }

    private func clamp(_ p: NSPoint) -> NSPoint {
        NSPoint(x: min(max(p.x, 0), bounds.width), y: min(max(p.y, 0), bounds.height))
    }

    private func hitWindow(at p: NSPoint) -> Int? {
        targets.firstIndex { $0.rect.contains(p) } // frontmost first
    }
}
