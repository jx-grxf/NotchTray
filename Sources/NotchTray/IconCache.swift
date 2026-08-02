import AppKit
import ImageIO
import UniformTypeIdentifiers

/// On-disk store for captured menu bar icons.
///
/// A status item can only be photographed while it is on screen —
/// ScreenCaptureKit refuses windows parked far off-screen, which is exactly
/// where every item NotchTray cares about ends up. So the capture has to be
/// taken opportunistically while the item is still visible and kept, including
/// across launches: an item that is already hidden when the app starts would
/// otherwise never get a real icon, only its app's generic one.
@MainActor
final class IconCache {
    private var memory: [String: CGImage] = [:]
    private let directory: URL

    init() {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        directory = base.appendingPathComponent("NotchTray/Icons", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true
        )
    }

    subscript(key: String) -> CGImage? {
        if let cached = memory[key] { return cached }
        guard let loaded = loadFromDisk(key) else { return nil }
        memory[key] = loaded
        return loaded
    }

    func store(_ image: CGImage, for key: String) {
        memory[key] = image
        writeToDisk(image, key: key)
    }

    /// File names have to survive keys containing slashes, spaces and dots.
    private func fileURL(for key: String) -> URL {
        let safe = key.unicodeScalars.map { scalar -> String in
            CharacterSet.alphanumerics.contains(scalar) ? String(scalar) : "_"
        }.joined()
        return directory.appendingPathComponent("\(safe).png")
    }

    private func loadFromDisk(_ key: String) -> CGImage? {
        let url = fileURL(for: key)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    private func writeToDisk(_ image: CGImage, key: String) {
        let url = fileURL(for: key)
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil
        ) else { return }
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
    }
}
