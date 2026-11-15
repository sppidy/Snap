import AppKit

/// Small floating preview in the bottom-right corner after each capture.
/// Click to open, drag to drop the file anywhere. Fades out on its own.
final class ThumbnailPanel: NSPanel {
    private static var current: ThumbnailPanel?
    private var dismissTask: Task<Void, Never>?

    static func show(image: CGImage, scale: CGFloat, url: URL, screen: NSScreen) {
        current?.dismiss(animated: false)

        let points = NSSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale)
        let fit = min(200 / points.width, 130 / points.height, 1)
        let size = NSSize(
            width: max(48, (points.width * fit).rounded()),
            height: max(36, (points.height * fit).rounded())
        )
        let visible = screen.visibleFrame
        let frame = NSRect(
            x: visible.maxX - size.width - 16,
            y: visible.minY + 16,
            width: size.width,
            height: size.height
        )

        let panel = ThumbnailPanel(
            contentRect: frame.offsetBy(dx: 0, dy: -12),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.isFloatingPanel = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]

        let view = ThumbnailView(frame: NSRect(origin: .zero, size: size), image: image, url: url, points: points)
        view.onClick = { [weak panel] in
            NSWorkspace.shared.open(url)
            panel?.dismiss()
        }
        view.onHover = { [weak panel] inside in
            if inside { panel?.dismissTask?.cancel() } else { panel?.scheduleDismiss() }
        }
        view.onDragBegan = { [weak panel] in
            panel?.dismissTask?.cancel()
            panel?.alphaValue = 0.35
        }
        view.onDragEnded = { [weak panel] dropped in
            if dropped { panel?.dismiss() } else { panel?.alphaValue = 1; panel?.scheduleDismiss() }
        }
        panel.contentView = view

        current = panel
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
            panel.animator().setFrame(frame, display: true)
        }
        panel.scheduleDismiss()
    }

    private func scheduleDismiss(after seconds: Double = 5) {
        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }

    private func dismiss(animated: Bool = true) {
        dismissTask?.cancel()
        dismissTask = nil
        if ThumbnailPanel.current === self { ThumbnailPanel.current = nil }
        guard animated else { orderOut(nil); return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.18
            self.animator().alphaValue = 0
        }, completionHandler: {
            MainActor.assumeIsolated { self.orderOut(nil) }
        })
    }
}

final class ThumbnailView: NSView, NSDraggingSource {
    var onClick: (() -> Void)?
    var onHover: ((Bool) -> Void)?
    var onDragBegan: (() -> Void)?
    var onDragEnded: ((Bool) -> Void)?

    private let url: URL
    private let preview: NSImage
    private var downAt: NSPoint?
    private var dragging = false

    init(frame: NSRect, image: CGImage, url: URL, points: NSSize) {
        self.url = url
        self.preview = NSImage(cgImage: image, size: points)
        super.init(frame: frame)

        let root = CALayer()
        root.contents = image
        root.contentsGravity = .resizeAspect
        root.backgroundColor = NSColor.black.withAlphaComponent(0.85).cgColor
        root.cornerRadius = 10
        root.cornerCurve = .continuous
        root.masksToBounds = true
        root.borderWidth = 1
        root.borderColor = NSColor.white.withAlphaComponent(0.22).cgColor
        layer = root
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self
        ))
    }

    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { if !dragging { onHover?(false) } }

    override func mouseDown(with event: NSEvent) {
        downAt = event.locationInWindow
    }

    override func mouseDragged(with event: NSEvent) {
        guard !dragging, let start = downAt else { return }
        let p = event.locationInWindow
        guard hypot(p.x - start.x, p.y - start.y) > 3 else { return }
        dragging = true
        onDragBegan?()
        let item = NSDraggingItem(pasteboardWriter: url as NSURL)
        item.setDraggingFrame(bounds, contents: preview)
        beginDraggingSession(with: [item], event: event, source: self)
    }

    override func mouseUp(with event: NSEvent) {
        if !dragging, downAt != nil { onClick?() }
        downAt = nil
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        dragging = false
        downAt = nil
        onDragEnded?(operation != [])
    }
}
