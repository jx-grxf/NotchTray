// Renders the DMG window background.
//
// Design language follows the app icon: near-black at the top fading into the
// icon's blue at the bottom, with the icon's triple-ring motif reused as the
// drag arrow. Emitted at 2x and tagged 144 dpi so Finder draws it crisply in a
// 660x400 window.
//
//   swift Scripts/make_dmg_background.swift <output.png>

import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

let designWidth: CGFloat = 660
let designHeight: CGFloat = 400
let scale: CGFloat = 2

let pixelWidth = Int(designWidth * scale)
let pixelHeight = Int(designHeight * scale)

guard
    let context = CGContext(
        data: nil,
        width: pixelWidth,
        height: pixelHeight,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
else {
    FileHandle.standardError.write(Data("error: could not create bitmap context\n".utf8))
    exit(1)
}

context.scaleBy(x: scale, y: scale)

/// CoreGraphics puts the origin bottom-left; the layout below is expressed in
/// top-left coordinates to match how the DMG window is described elsewhere.
func flip(_ y: CGFloat) -> CGFloat { designHeight - y }

func rgb(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha)
}

// MARK: - Backdrop

let backdrop = CGGradient(
    colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
    colors: [rgb(0x03050A), rgb(0x061020), rgb(0x0B1D38)] as CFArray,
    locations: [0, 0.55, 1])!

context.drawLinearGradient(
    backdrop,
    start: CGPoint(x: 0, y: designHeight),
    end: CGPoint(x: 0, y: 0),
    options: [])

// A soft pool of the icon's blue, low on the canvas, so the window reads as lit
// from below rather than flatly dark.
let glow = CGGradient(
    colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
    colors: [rgb(0x3B8CFF, alpha: 0.30), rgb(0x3B8CFF, alpha: 0.0)] as CFArray,
    locations: [0, 1])!

context.drawRadialGradient(
    glow,
    startCenter: CGPoint(x: designWidth / 2, y: flip(430)), startRadius: 0,
    endCenter: CGPoint(x: designWidth / 2, y: flip(430)), endRadius: 330,
    options: [])

// MARK: - Text

func draw(
    _ string: String, size: CGFloat, weight: CGFloat, color: CGColor,
    centeredAt x: CGFloat, baseline y: CGFloat, tracking: CGFloat = 0
) {
    let descriptor = CTFontDescriptor.systemDescriptor(size: size, weight: weight)
    let font = CTFontCreateWithFontDescriptor(descriptor, size, nil)

    // CoreText attribute keys, not the AppKit ones — this script deliberately
    // avoids importing AppKit so it stays runnable as a plain `swift` script.
    var attributes: [CFString: Any] = [
        kCTFontAttributeName: font,
        kCTForegroundColorAttributeName: color,
    ]
    if tracking != 0 {
        attributes[kCTKernAttributeName] = tracking
    }

    let attributed = CFAttributedStringCreate(
        nil, string as CFString, attributes as CFDictionary)!
    let line = CTLineCreateWithAttributedString(attributed)
    let width = CTLineGetTypographicBounds(line, nil, nil, nil)

    context.textPosition = CGPoint(x: x - CGFloat(width) / 2, y: flip(y))
    CTLineDraw(line, context)
}

extension CTFontDescriptor {
    static func systemDescriptor(size: CGFloat, weight: CGFloat) -> CTFontDescriptor {
        let base = CTFontDescriptorCreateWithAttributes(
            [
                kCTFontNameAttribute: ".AppleSystemUIFont" as CFString
            ] as CFDictionary)
        return CTFontDescriptorCreateCopyWithAttributes(
            base,
            [
                kCTFontTraitsAttribute: [kCTFontWeightTrait: weight]
            ] as CFDictionary)
    }
}

draw(
    "NotchTray", size: 34, weight: 0.3, color: rgb(0xFFFFFF),
    centeredAt: designWidth / 2, baseline: 78, tracking: 0.4)

draw(
    "Drag NotchTray into your Applications folder",
    size: 14, weight: 0, color: rgb(0x8FA6C4),
    centeredAt: designWidth / 2, baseline: 108)

// MARK: - Drag arrow

// Three rings, echoing the app icon, marching from the app toward Applications.
// Each ring is a little brighter and larger than the last, so the row reads as
// a direction rather than as decoration.
let ringCenterY = flip(232)
let ringSpacing: CGFloat = 30
let ringOrigin = designWidth / 2 - ringSpacing

for index in 0..<3 {
    let progress = CGFloat(index) / 2
    let outerRadius = 9 + progress * 2.5
    let lineWidth = 3.0 + progress * 0.7
    let alpha = 0.30 + progress * 0.55
    let center = CGPoint(x: ringOrigin + CGFloat(index) * ringSpacing, y: ringCenterY)

    context.setStrokeColor(rgb(0x5EA6FF, alpha: alpha))
    context.setLineWidth(lineWidth)
    context.strokeEllipse(
        in: CGRect(
            x: center.x - outerRadius, y: center.y - outerRadius,
            width: outerRadius * 2, height: outerRadius * 2))
}

// MARK: - Output

guard let image = context.makeImage() else {
    FileHandle.standardError.write(Data("error: could not render image\n".utf8))
    exit(1)
}

let outputPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "dmg-background.png"
let url = URL(fileURLWithPath: outputPath)

guard
    let destination = CGImageDestinationCreateWithURL(
        url as CFURL, UTType.png.identifier as CFString, 1, nil)
else {
    FileHandle.standardError.write(Data("error: could not open \(outputPath)\n".utf8))
    exit(1)
}

// 144 dpi tells Finder to draw the 2x bitmap at the 660x400 design size.
CGImageDestinationAddImage(
    destination, image,
    [
        kCGImagePropertyDPIWidth: 144,
        kCGImagePropertyDPIHeight: 144,
    ] as CFDictionary)

guard CGImageDestinationFinalize(destination) else {
    FileHandle.standardError.write(Data("error: could not write \(outputPath)\n".utf8))
    exit(1)
}

print("Created \(outputPath) (\(pixelWidth)x\(pixelHeight) @144dpi)")
