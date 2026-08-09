#!/usr/bin/env swift

import AppKit
import Foundation

guard CommandLine.arguments.count == 3 else {
    fputs("用法：generate-icon.swift <源 PNG> <输出 ICNS>\n", stderr)
    exit(64)
}

let sourceURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])

guard let sourceImage = NSImage(contentsOf: sourceURL) else {
    fputs("无法读取源图片：\(sourceURL.path)\n", stderr)
    exit(65)
}

let representations: [(type: String, pixels: Int)] = [
    ("icp4", 16),
    ("icp5", 32),
    ("icp6", 64),
    ("ic07", 128),
    ("ic08", 256),
    ("ic09", 512),
    ("ic10", 1024),
]

func bigEndianBytes(_ value: UInt32) -> Data {
    var bigEndianValue = value.bigEndian
    return Data(bytes: &bigEndianValue, count: MemoryLayout<UInt32>.size)
}

func pngData(for pixels: Int) -> Data? {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        return nil
    }

    bitmap.size = NSSize(width: pixels, height: pixels)
    guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        return nil
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    sourceImage.draw(
        in: NSRect(x: 0, y: 0, width: pixels, height: pixels),
        from: NSRect(origin: .zero, size: sourceImage.size),
        operation: .copy,
        fraction: 1
    )
    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()

    return bitmap.representation(using: .png, properties: [:])
}

var body = Data()
for representation in representations {
    guard let png = pngData(for: representation.pixels) else {
        fputs("无法生成 \(representation.pixels)×\(representation.pixels) 图标。\n", stderr)
        exit(66)
    }

    body.append(Data(representation.type.utf8))
    body.append(bigEndianBytes(UInt32(png.count + 8)))
    body.append(png)
}

var icon = Data("icns".utf8)
icon.append(bigEndianBytes(UInt32(body.count + 8)))
icon.append(body)

do {
    try icon.write(to: outputURL, options: .atomic)
    print(outputURL.path)
} catch {
    fputs("无法写入 ICNS：\(error.localizedDescription)\n", stderr)
    exit(73)
}
