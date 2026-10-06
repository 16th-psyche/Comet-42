import AppKit
import Carbon.HIToolbox
import PDFKit

/// Remembers when the clipboard last changed, so a fresh screenshot can be told from an old one.
@Observable
final class ClipboardWatcher {
    @ObservationIgnored private var lastChangeCount = NSPasteboard.general.changeCount
    @ObservationIgnored private(set) var lastChangeAt = Date.distantPast
    @ObservationIgnored private var timer: Timer?

    /// How long a copied picture counts as "just taken" and is attached without asking.
    static let freshness: TimeInterval = 120

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
    }

    private func poll() {
        let count = NSPasteboard.general.changeCount
        guard count != lastChangeCount else { return }
        lastChangeCount = count
        lastChangeAt = Date()
    }

    var isFresh: Bool { Date().timeIntervalSince(lastChangeAt) < Self.freshness }

    /// Accepts the change our own restore made, so it never looks like a new copy.
    func acknowledgeOwnChange(keepingDate date: Date? = nil) {
        lastChangeCount = NSPasteboard.general.changeCount
        if let date { lastChangeAt = date }
    }
}

/// A picture or file the panel stages beside the question.
struct StagedImage: Identifiable, Equatable {
    let id = UUID()
    let image: AIImage
    let thumbnail: NSImage
    let name: String
}

enum ClipboardImage {
    private static let maxImageEdge: CGFloat = 1_568
    private static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "webp", "heic", "tiff", "bmp"
    ]

    /// A screenshot sits on the pasteboard as TIFF/PNG; a copied Finder file as a file URL.
    static func read(from pasteboard: NSPasteboard = .general) -> StagedImage? {
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL],
            let file = urls.first(where: {
                $0.isFileURL && imageExtensions.contains($0.pathExtension.lowercased())
            }),
            let data = try? Data(contentsOf: file)
        {
            return stage(data, name: file.lastPathComponent)
        }
        for type in [NSPasteboard.PasteboardType.png, .tiff] {
            if let data = pasteboard.data(forType: type) { return stage(data, name: "Screenshot") }
        }
        return nil
    }

    static func stage(_ data: Data, name: String) -> StagedImage? {
        guard let source = NSBitmapImageRep(data: data),
            let png = bounded(source),
            let thumbnail = NSImage(data: png)
        else { return nil }
        return StagedImage(
            image: AIImage(data: png, mimeType: "image/png"), thumbnail: thumbnail, name: name)
    }

    private static func bounded(_ source: NSBitmapImageRep) -> Data? {
        let width = CGFloat(source.pixelsWide)
        let height = CGFloat(source.pixelsHigh)
        guard max(width, height) > maxImageEdge else {
            return source.representation(using: .png, properties: [:])
        }
        let scale = maxImageEdge / max(width, height)
        let size = NSSize(width: (width * scale).rounded(), height: (height * scale).rounded())
        guard
            let scaled = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
            let context = NSGraphicsContext(bitmapImageRep: scaled)
        else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        source.draw(in: NSRect(origin: .zero, size: size))
        NSGraphicsContext.restoreGraphicsState()
        return scaled.representation(using: .png, properties: [:])
    }
}

/// What a paste or a drop turns into: context to stage, text for the composer, or a refusal.
enum PastedContent {
    case image(StagedImage)
    case text(StagedText)
    case inline(String)
    case refused(String)

    /// Past this a paste is material to work on, not a question, so it becomes a chip.
    static let inlineCharacterLimit = 300
    static let inlineLineLimit = 4
    static let maxTextBytes = SelectionReader.maxSelectionBytes

    private static let textExtensions: Set<String> = [
        "txt", "md", "markdown", "csv", "tsv", "json", "jsonl", "yaml", "yml", "toml", "ini",
        "xml", "html", "css", "js", "jsx", "ts", "tsx", "swift", "m", "h", "c", "cc", "cpp",
        "rs", "go", "rb", "py", "php", "java", "kt", "sh", "zsh", "sql", "log", "rtf"
    ]
    private static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "webp", "heic", "tiff", "bmp"
    ]

    /// Files first (a copied Finder file also carries its name as text), then pictures, then text.
    static func read(from pasteboard: NSPasteboard = .general) -> [PastedContent] {
        if let urls = pasteboard.readObjects(
            forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
            !urls.isEmpty
        {
            return urls.map(file)
        }
        if let image = ClipboardImage.read(from: pasteboard) { return [.image(image)] }
        if let string = pasteboard.string(forType: .string), !string.isEmpty {
            return [text(string)]
        }
        return []
    }

    static func text(_ string: String) -> PastedContent {
        let lines = string.split(separator: "\n", omittingEmptySubsequences: false).count
        guard string.count > inlineCharacterLimit || lines > inlineLineLimit else {
            return .inline(string)
        }
        return .text(StagedText(kind: .pasted, text: capped(string)))
    }

    static func file(_ url: URL) -> PastedContent {
        let name = url.lastPathComponent
        let ext = url.pathExtension.lowercased()
        if imageExtensions.contains(ext) {
            guard let data = try? Data(contentsOf: url), let image = ClipboardImage.stage(data, name: name)
            else { return .refused("\(name) could not be read as an image.") }
            return .image(image)
        }
        if ext == "pdf" {
            guard let document = PDFDocument(url: url), let string = document.string,
                !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { return .refused("\(name) has no text Comet 42 can read.") }
            return .text(StagedText(kind: .file(name), text: capped(string)))
        }
        if textExtensions.contains(ext) {
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            guard size <= maxTextBytes * 4 else { return .refused("\(name) is too large to attach.") }
            let string: String?
            if ext == "rtf" {
                string = (try? NSAttributedString(url: url, options: [:], documentAttributes: nil))?.string
            } else {
                string = try? String(contentsOf: url, encoding: .utf8)
            }
            guard let string else { return .refused("\(name) is not readable text.") }
            return .text(StagedText(kind: .file(name), text: capped(string)))
        }
        return .refused("Comet 42 can’t attach .\(ext.isEmpty ? "that" : ext) files.")
    }

    private static func capped(_ string: String) -> String {
        guard string.utf8.count > maxTextBytes else { return string }
        return String(string.utf8.prefix(maxTextBytes)) ?? String(string.prefix(maxTextBytes / 4))
    }
}

/// Puts a result back over the selection it came from.
enum TextReplacer {
    enum Outcome {
        case pasted
        /// The target could not take text, so the result went to the clipboard instead.
        case copied
    }

    static func replace(
        with text: String, in app: NSRunningApplication?, watcher: ClipboardWatcher
    ) async -> Outcome {
        guard let app, Permissions.isAccessibilityTrusted, !app.isTerminated else {
            copy(text, watcher: watcher)
            return .copied
        }
        app.activate()
        for _ in 0..<40 where NSWorkspace.shared.frontmostApplication != app {
            try? await Task.sleep(for: .milliseconds(25))
        }
        // Give the target's window a beat to take key focus back before typing into it.
        try? await Task.sleep(for: .milliseconds(80))
        guard AccessibilityText.isEditable(in: app) != false else {
            copy(text, watcher: watcher)
            return .copied
        }
        let pasteboard = NSPasteboard.general
        let snapshot = PasteboardSnapshot(pasteboard)
        let copiedAt = watcher.lastChangeAt
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        await KeySynth.waitForModifierRelease()
        KeySynth.command(CGKeyCode(kVK_ANSI_V))
        // The target reads the pasteboard asynchronously; restoring too soon pastes the old item.
        try? await Task.sleep(for: .milliseconds(450))
        snapshot.restore(to: pasteboard)
        watcher.acknowledgeOwnChange(keepingDate: copiedAt)
        return .pasted
    }

    static func copy(_ text: String, watcher: ClipboardWatcher) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        watcher.acknowledgeOwnChange()
    }
}
