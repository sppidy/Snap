import AppKit
import ImageIO
import UniformTypeIdentifiers

enum Settings {
    /// Captures always go to the clipboard. true = also save a PNG to `folder`.
    static var saveToFolder: Bool {
        get { UserDefaults.standard.object(forKey: "saveToFolder") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "saveToFolder") }
    }

    static var playSound: Bool {
        get { UserDefaults.standard.object(forKey: "playSound") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "playSound") }
    }

    static var folder: URL {
        get {
            if let path = UserDefaults.standard.string(forKey: "folder") {
                return URL(fileURLWithPath: path, isDirectory: true)
            }
            return FileManager.default.homeDirectoryForCurrentUser
                .appending(path: "Pictures/Screenshots", directoryHint: .isDirectory)
        }
        set { UserDefaults.standard.set(newValue.path, forKey: "folder") }
    }
}

/// Every capture: copy to clipboard, optionally save a PNG, then show the thumbnail.
@MainActor
enum Output {
    private static let sound: NSSound? = {
        let path = "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/system/Screen Capture.aif"
        return NSSound(contentsOfFile: path, byReference: true) ?? NSSound(named: "Tink")
    }()

    static func deliver(_ image: CGImage, scale: CGFloat, screen: NSScreen?) {
        guard let png = pngData(image, scale: scale) else { NSSound.beep(); return }
        copyToClipboard(png: png, image: image)
        if Settings.playSound { sound?.stop(); sound?.play() }
        guard let url = write(png) else { return }
        let screen = screen ?? NSScreen.main ?? NSScreen.screens[0]
        ThumbnailPanel.show(image: image, scale: scale, url: url, screen: screen)
    }

    private static func pngData(_ image: CGImage, scale: CGFloat) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            return nil
        }
        // Retina shots get 144 dpi so they open at their on-screen size.
        let dpi = 72 * scale
        let props = [kCGImagePropertyDPIWidth: dpi, kCGImagePropertyDPIHeight: dpi] as CFDictionary
        CGImageDestinationAddImage(dest, image, props)
        return CGImageDestinationFinalize(dest) ? data as Data : nil
    }

    private static func copyToClipboard(png: Data, image: CGImage) {
        let pb = NSPasteboard.general
        pb.clearContents()
        let tiff = NSBitmapImageRep(cgImage: image).tiffRepresentation
        pb.declareTypes(tiff == nil ? [.png] : [.png, .tiff], owner: nil)
        pb.setData(png, forType: .png)
        if let tiff { pb.setData(tiff, forType: .tiff) }
    }

    /// Saves to the chosen folder, or to a temp folder when saving is off
    /// (the thumbnail still needs a file to open / drag).
    private static func write(_ png: Data) -> URL? {
        let fm = FileManager.default
        let dir = Settings.saveToFolder
            ? Settings.folder
            : fm.temporaryDirectory.appending(path: "Snap", directoryHint: .isDirectory)
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            let base = "Screenshot " + timestamp()
            var url = dir.appending(path: base + ".png")
            var n = 2
            while fm.fileExists(atPath: url.path) {
                url = dir.appending(path: "\(base) (\(n)).png")
                n += 1
            }
            try png.write(to: url, options: .atomic)
            return url
        } catch {
            NSLog("Snap: could not save screenshot: \(error.localizedDescription)")
            return nil
        }
    }

    private static func timestamp() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return f.string(from: Date())
    }
}
