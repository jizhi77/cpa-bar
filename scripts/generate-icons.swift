import AppKit
import Foundation

let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let sourceURL = rootURL.appendingPathComponent("Assets/AppIcon-source-codex-gauge.png")
let outputURL = rootURL.appendingPathComponent("Assets/AppIcon-1024.png")
let iconsetURL = rootURL.appendingPathComponent("Assets/AppIcon.iconset")
let icnsURL = rootURL.appendingPathComponent("Assets/AppIcon.icns")

let iconSizes: [(name: String, size: Int)] = [
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

func runProcess(_ launchPath: String, _ arguments: [String]) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: launchPath)
    process.arguments = arguments
    try process.run()
    process.waitUntilExit()

    guard process.terminationStatus == 0 else {
        throw NSError(
            domain: "IconGeneration",
            code: Int(process.terminationStatus),
            userInfo: [
                NSLocalizedDescriptionKey: "Command failed: \(launchPath) \(arguments.joined(separator: " "))",
            ]
        )
    }
}

func writePNG(_ image: NSImage, to url: URL, size: Int) throws {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        throw NSError(
            domain: "IconGeneration",
            code: 2,
            userInfo: [NSLocalizedDescriptionKey: "Unable to allocate bitmap \(url.lastPathComponent)"]
        )
    }

    NSGraphicsContext.saveGraphicsState()
    if let context = NSGraphicsContext(bitmapImageRep: bitmap) {
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        image.draw(
            in: NSRect(x: 0, y: 0, width: size, height: size),
            from: NSRect(origin: .zero, size: image.size),
            operation: .copy,
            fraction: 1
        )
        context.flushGraphics()
    }
    NSGraphicsContext.restoreGraphicsState()

    guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(
            domain: "IconGeneration",
            code: 2,
            userInfo: [NSLocalizedDescriptionKey: "Unable to render PNG \(url.lastPathComponent)"]
        )
    }

    try pngData.write(to: url)
}

guard let sourceImage = NSImage(contentsOf: sourceURL),
      let sourceTIFF = sourceImage.tiffRepresentation,
      let sourceBitmap = NSBitmapImageRep(data: sourceTIFF),
      let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: sourceBitmap.pixelsWide,
        pixelsHigh: sourceBitmap.pixelsHigh,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
      ) else {
    fputs("Unable to load icon source at \(sourceURL.path)\n", stderr)
    exit(1)
}

NSGraphicsContext.saveGraphicsState()
if let context = NSGraphicsContext(bitmapImageRep: bitmap) {
    NSGraphicsContext.current = context
    sourceImage.draw(in: NSRect(x: 0, y: 0, width: bitmap.pixelsWide, height: bitmap.pixelsHigh))
    context.flushGraphics()
}
NSGraphicsContext.restoreGraphicsState()

guard let data = bitmap.bitmapData else {
    fputs("Unable to access bitmap data.\n", stderr)
    exit(1)
}

let bytesPerRow = bitmap.bytesPerRow
let samplesPerPixel = bitmap.samplesPerPixel

for y in 0..<bitmap.pixelsHigh {
    for x in 0..<bitmap.pixelsWide {
        let offset = y * bytesPerRow + x * samplesPerPixel
        let red = Double(data[offset]) / 255.0
        let green = Double(data[offset + 1]) / 255.0
        let blue = Double(data[offset + 2]) / 255.0
        let brightness = max(red, green, blue)

        if brightness < 0.025 {
            data[offset + 3] = 0
        }
    }
}

guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
    fputs("Unable to encode cleaned app icon.\n", stderr)
    exit(1)
}

let cleanedImage = NSImage(data: pngData)
guard let cleanedImage else {
    fputs("Unable to reload cleaned app icon.\n", stderr)
    exit(1)
}

try writePNG(cleanedImage, to: outputURL, size: 1024)

try? FileManager.default.removeItem(at: iconsetURL)
try FileManager.default.createDirectory(
    at: iconsetURL,
    withIntermediateDirectories: true,
    attributes: nil
)

for iconSize in iconSizes {
    try writePNG(cleanedImage, to: iconsetURL.appendingPathComponent(iconSize.name), size: iconSize.size)
}

try? FileManager.default.removeItem(at: icnsURL)
try runProcess("/usr/bin/iconutil", ["-c", "icns", iconsetURL.path, "-o", icnsURL.path])

print(outputURL.path)
print(icnsURL.path)
