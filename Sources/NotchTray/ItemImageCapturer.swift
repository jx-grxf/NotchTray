import AppKit
import ScreenCaptureKit

/// Captures the actual rendered pixels of hidden status items so the panel
/// can show the real menu bar icons instead of app icons.
///
/// Status item windows live at window layer 25 (hosted by Control Center on
/// macOS 26). ScreenCaptureKit can screenshot an individual window even while
/// it is occluded by the notch or parked off-screen, which is exactly the
/// state hidden items are in. Requires Screen Recording permission; callers
/// fall back to app icons when unavailable.
@MainActor
final class ItemImageCapturer {

    private static let statusItemWindowLayer = 25

    var hasPermission: Bool { CGPreflightScreenCaptureAccess() }

    private var didRequestPermission = false

    func requestPermissionIfNeeded() {
        guard !hasPermission, !didRequestPermission else { return }
        didRequestPermission = true
        CGRequestScreenCaptureAccess()
    }

    /// Returns a map of item id → captured icon image.
    func capture(items: [MenuBarItem]) async -> [String: CGImage] {
        guard hasPermission, !items.isEmpty else { return [:] }
        guard let content = try? await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: false
        ) else { return [:] }

        let candidates = content.windows.filter {
            $0.windowLayer == Self.statusItemWindowLayer && $0.frame.width < 400
        }

        var result: [String: CGImage] = [:]
        for item in items {
            let itemCenterX = item.frame.midX
            guard let window = candidates.min(by: {
                abs($0.frame.midX - itemCenterX) < abs($1.frame.midX - itemCenterX)
            }), abs(window.frame.midX - itemCenterX) < 8 else { continue }

            let config = SCStreamConfiguration()
            config.width = Int(window.frame.width) * 2
            config.height = Int(window.frame.height) * 2
            config.showsCursor = false
            config.captureResolution = .best

            let filter = SCContentFilter(desktopIndependentWindow: window)
            if let image = try? await SCScreenshotManager.captureImage(
                contentFilter: filter, configuration: config
            ) {
                result[item.id] = Self.croppedToContent(image)
            }
        }
        return result
    }

    /// Status item windows are ~39 pt tall with the glyph centered in lots of
    /// transparent padding; displayed as-is the glyph looks tiny. Crop to the
    /// visible (non-transparent) pixels with a small margin.
    private static func croppedToContent(_ image: CGImage) -> CGImage {
        let width = image.width, height = image.height
        guard width > 0, height > 0,
              let context = CGContext(
                data: nil, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return image }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let data = context.data else { return image }

        let pixels = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            for x in 0..<width where pixels[(y * width + x) * 4 + 3] > 16 {
                if x < minX { minX = x }
                if x > maxX { maxX = x }
                if y < minY { minY = y }
                if y > maxY { maxY = y }
            }
        }
        guard maxX >= minX, maxY >= minY else { return image }

        let margin = 2
        let box = CGRect(
            x: max(0, minX - margin),
            y: max(0, minY - margin),
            width: min(width, maxX + margin + 1) - max(0, minX - margin),
            height: min(height, maxY + margin + 1) - max(0, minY - margin)
        )
        return image.cropping(to: box) ?? image
    }
}
