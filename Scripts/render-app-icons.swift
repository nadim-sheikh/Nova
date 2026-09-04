#!/usr/bin/env swift
// Renders Nova's light-mode and dark-mode app icons as sharp 1024x1024 PNGs.
//
//   swift Scripts/render-app-icons.swift            # installs into Nova/Assets.xcassets
//   swift Scripts/render-app-icons.swift <outDir>
//
// The colours and proportions come from the original assets/icon-source/appicon-light.ico and appicon-dark.ico
// artwork, redrawn as vectors so every icon size stays crisp and the corners are transparent.
import AppKit

struct Stop {
    let location: CGFloat
    let color: NSColor
}

struct IconStyle {
    let name: String
    let background: [Stop]
    let mark: [Stop]
}

func rgb(_ hex: UInt32) -> NSColor {
    NSColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: 1
    )
}

/// Apple-style squircle: a superellipse, which matches the macOS icon shape far better than a
/// plain rounded rectangle does.
func squircle(in rect: CGRect, exponent: CGFloat = 5, steps: Int = 1440) -> CGPath {
    let path = CGMutablePath()
    let centre = CGPoint(x: rect.midX, y: rect.midY)
    let a = rect.width / 2, b = rect.height / 2
    let power = 2 / exponent
    for step in 0...steps {
        let angle = 2 * CGFloat.pi * CGFloat(step) / CGFloat(steps)
        let cosine = cos(angle), sine = sin(angle)
        let x = centre.x + a * (cosine < 0 ? -1 : 1) * pow(abs(cosine), power)
        let y = centre.y + b * (sine < 0 ? -1 : 1) * pow(abs(sine), power)
        step == 0 ? path.move(to: CGPoint(x: x, y: y)) : path.addLine(to: CGPoint(x: x, y: y))
    }
    path.closeSubpath()
    return path
}

/// Right-pointing play triangle with softly rounded corners, sized to `rect`.
func playMark(in rect: CGRect, cornerRadius: CGFloat) -> CGPath {
    let vertices = [
        CGPoint(x: rect.minX, y: rect.minY),
        CGPoint(x: rect.maxX, y: rect.midY),
        CGPoint(x: rect.minX, y: rect.maxY),
    ]
    let path = CGMutablePath()
    // Start partway along the first edge, then round each corner in turn: `addArc` takes the
    // corner to round followed by the next corner along the path.
    path.move(to: CGPoint(x: (vertices[0].x + vertices[1].x) / 2, y: (vertices[0].y + vertices[1].y) / 2))
    for index in 0..<vertices.count {
        path.addArc(tangent1End: vertices[(index + 1) % vertices.count],
                    tangent2End: vertices[(index + 2) % vertices.count],
                    radius: cornerRadius)
    }
    path.closeSubpath()
    return path
}

func draw(_ style: IconStyle, size: CGFloat) -> Data? {
    guard let context = CGContext(
        data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }

    func gradient(_ stops: [Stop]) -> CGGradient? {
        CGGradient(colorsSpace: context.colorSpace,
                   colors: stops.map { $0.color.cgColor } as CFArray,
                   locations: stops.map { $0.location })
    }

    // Apple's macOS grid: the shape fills about 80% of the canvas, leaving a transparent margin.
    let inset = size * 0.098
    let shapeRect = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)

    context.saveGState()
    context.addPath(squircle(in: shapeRect))
    context.clip()
    if let background = gradient(style.background) {
        context.drawLinearGradient(background,
                                   start: CGPoint(x: 0, y: shapeRect.maxY),
                                   end: CGPoint(x: 0, y: shapeRect.minY),
                                   options: [])
    }
    context.restoreGState()

    // The mark's bounding box is centred, matching the source artwork.
    let markSize = size * 0.46
    let markRect = CGRect(x: (size - markSize) / 2, y: (size - markSize) / 2, width: markSize, height: markSize)
    context.saveGState()
    context.addPath(playMark(in: markRect, cornerRadius: markSize * 0.07))
    context.clip()
    if let mark = gradient(style.mark) {
        context.drawLinearGradient(mark,
                                   start: CGPoint(x: markRect.midX, y: markRect.maxY),
                                   end: CGPoint(x: markRect.midX, y: markRect.minY),
                                   options: [])
    }
    context.restoreGState()

    guard let image = context.makeImage() else { return nil }
    return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
}

let styles = [
    IconStyle(
        name: "AppIconLight",
        background: [Stop(location: 0, color: rgb(0xFAFCFD)), Stop(location: 1, color: rgb(0xEDF3F9))],
        mark: [Stop(location: 0, color: rgb(0x9BDBFB)), Stop(location: 0.45, color: rgb(0x3492FA)),
               Stop(location: 1, color: rgb(0x0047CB))]
    ),
    IconStyle(
        name: "AppIconDark",
        background: [Stop(location: 0, color: rgb(0x34373C)), Stop(location: 1, color: rgb(0x07070A))],
        mark: [Stop(location: 0, color: rgb(0xEDEFF3)), Stop(location: 0.5, color: rgb(0x9AA0AA)),
               Stop(location: 1, color: rgb(0x2A2E37))]
    ),
]

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let outputRoot = CommandLine.arguments.count > 1
    ? URL(fileURLWithPath: CommandLine.arguments[1])
    : root.appendingPathComponent("Nova/Assets.xcassets")

for style in styles {
    guard let data = draw(style, size: 1024) else {
        print("could not render \(style.name)")
        exit(1)
    }
    let directory = outputRoot.appendingPathComponent("\(style.name).imageset")
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let file = directory.appendingPathComponent("\(style.name).png")
    do {
        try data.write(to: file)
        let contents = """
        {
          "images" : [
            {
              "filename" : "\(style.name).png",
              "idiom" : "universal"
            }
          ],
          "info" : {
            "author" : "xcode",
            "version" : 1
          }
        }
        """
        try contents.write(to: directory.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
        print("rendered \(style.name).png at 1024x1024")
    } catch {
        print("could not write \(file.path): \(error.localizedDescription)")
        exit(1)
    }
}
