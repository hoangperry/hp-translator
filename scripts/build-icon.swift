#!/usr/bin/env swift
//
// Generates the macOS app icon for Contextual Mac Translator.
//
// Design: full-bleed hanko-red squircle background + ivory 訳 character
// rendered in Hiragino Mincho ProN W6, mimicking a Japanese seal stamp.
// Matches the `.hanko-mark` brand element used across the marketing site.
//
// Output: scripts/AppIcon.iconset/*.png + scripts/AppIcon.icns
// Usage: `swift scripts/build-icon.swift` from translator-app root.
//

import AppKit
import CoreText
import Foundation

let iconSizes: [(name: String, pixels: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

// Match the marketing site's accent palette:
// --color-accent ≈ oklch(52% 0.19 25) → sRGB ≈ #B82A23
let hankoRed = NSColor(srgbRed: 0.722, green: 0.165, blue: 0.137, alpha: 1.0)
// --color-surface ≈ oklch(98.5% 0.003 60) → sRGB ≈ #F8F6F2
let ivory = NSColor(srgbRed: 0.973, green: 0.965, blue: 0.949, alpha: 1.0)

func renderIcon(pixelSize: Int) -> Data? {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelSize,
        pixelsHigh: pixelSize,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 32
    ) else {
        FileHandle.standardError.write(Data("Failed to allocate bitmap for \(pixelSize)\n".utf8))
        return nil
    }

    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }

    guard let gctx = NSGraphicsContext(bitmapImageRep: bitmap) else {
        FileHandle.standardError.write(Data("Failed to create graphics context\n".utf8))
        return nil
    }
    NSGraphicsContext.current = gctx
    gctx.imageInterpolation = .high
    gctx.shouldAntialias = true

    let dim = CGFloat(pixelSize)
    let rect = NSRect(x: 0, y: 0, width: dim, height: dim)

    // Squircle background — Apple's macOS template uses ~22.5% corner radius.
    let cornerRadius = dim * 0.225
    let bgPath = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
    hankoRed.setFill()
    bgPath.fill()

    // 訳 character. Hiragino Mincho W6 reads cleanly at small sizes and
    // gives the seal-script weight. The fallback chain handles edge cases.
    let fontSize = dim * 0.62
    let font = NSFont(name: "Hiragino Mincho ProN W6", size: fontSize)
        ?? NSFont(name: "Hiragino Mincho Pro W6", size: fontSize)
        ?? NSFont(name: "Hiragino Sans W7", size: fontSize)
        ?? NSFont.systemFont(ofSize: fontSize, weight: .heavy)

    let attrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: ivory,
    ]
    let str = NSAttributedString(string: "訳", attributes: attrs)
    let strSize = str.size()
    // Nudge slightly up so the optical centre of the CJK glyph lands at the
    // geometric centre (the glyph box has more whitespace below the mark).
    let drawRect = NSRect(
        x: (dim - strSize.width) / 2,
        y: (dim - strSize.height) / 2 + dim * 0.02,
        width: strSize.width,
        height: strSize.height
    )
    str.draw(in: drawRect)

    return bitmap.representation(using: .png, properties: [:])
}

let scriptDir = URL(fileURLWithPath: CommandLine.arguments[0])
    .deletingLastPathComponent()
let iconsetURL = scriptDir.appendingPathComponent("AppIcon.iconset")
let icnsURL = scriptDir.appendingPathComponent("AppIcon.icns")

let fm = FileManager.default
try? fm.removeItem(at: iconsetURL)
try? fm.removeItem(at: icnsURL)
try fm.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

for entry in iconSizes {
    guard let data = renderIcon(pixelSize: entry.pixels) else { exit(1) }
    let out = iconsetURL.appendingPathComponent(entry.name)
    try data.write(to: out)
    print("  \(entry.name) (\(entry.pixels)×\(entry.pixels))")
}

let process = Process()
process.launchPath = "/usr/bin/iconutil"
process.arguments = ["-c", "icns", iconsetURL.path, "-o", icnsURL.path]
try process.run()
process.waitUntilExit()

if process.terminationStatus == 0 {
    print("\n✓ AppIcon.icns → \(icnsURL.path)")
} else {
    FileHandle.standardError.write(Data("iconutil failed: status \(process.terminationStatus)\n".utf8))
    exit(1)
}
