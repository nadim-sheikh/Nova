#!/usr/bin/env swift
// Renders the background artwork shown inside Nova's installer window.
//
//   swift Scripts/render-dmg-background.swift <outputDirectory> [light|dark]
//
// Writes background.png (660x420) and background@2x.png; make-dmg.sh combines them into the
// multi-resolution TIFF that Finder displays. Finder shows whichever image is baked into the disk
// image, so the theme is chosen at build time and is the same for everyone who opens it.
import AppKit

let windowWidth: CGFloat = 660
let windowHeight: CGFloat = 420
/// Finder measures icon positions from the top of the window, so mirror them when drawing.
let iconCentreFromTop: CGFloat = 214
let appIconX: CGFloat = 168
let applicationsX: CGFloat = 492

struct Palette {
    let backdropTop: UInt32
    let backdropBottom: UInt32
    let wordmark: UInt32
    let tagline: UInt32
    let instruction: UInt32
    let credit: UInt32
    let arrow: UInt32
    /// Drawn behind each icon so Finder's file names stay readable whichever label colour it picks.
    let labelPlate: UInt32
    let labelPlateAlpha: CGFloat

    static let light = Palette(
        backdropTop: 0xFCFDFE, backdropBottom: 0xEBF0F7, wordmark: 0x161B22, tagline: 0x6B7480,
        instruction: 0x39414D, credit: 0x98A0AC, arrow: 0x3492FA, labelPlate: 0xFFFFFF, labelPlateAlpha: 0
    )
    /// Finder draws a disk image's file names itself, always in dark text, and offers no way to
    /// colour them. Set `labelPlateAlpha` above zero to put a light plate behind each name; at zero
    /// the names sit straight on the backdrop, which is cleaner but faint on a dark one.
    static let dark = Palette(
        backdropTop: 0x2A2D33, backdropBottom: 0x15171B, wordmark: 0xF6F8FB, tagline: 0x99A2AE,
        instruction: 0xDCE1E8, credit: 0x6E7681, arrow: 0x4B9BFB, labelPlate: 0xE7ECF3, labelPlateAlpha: 0
    )
}

func rgb(_ hex: UInt32, alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha)
}

func draw(text: String, font: NSFont, color: NSColor, centredAt point: CGPoint) {
    let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
    let string = NSAttributedString(string: text, attributes: attributes)
    let size = string.size()
    string.draw(at: CGPoint(x: point.x - size.width / 2, y: point.y - size.height / 2))
}

func renderBackground(scale: CGFloat, palette: Palette) -> NSBitmapImageRep? {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(windowWidth * scale), pixelsHigh: Int(windowHeight * scale),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else { return nil }
    rep.size = NSSize(width: windowWidth, height: windowHeight)

    guard let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context

    // Soft vertical wash, a touch cooler at the bottom.
    let backdrop = NSGradient(starting: rgb(palette.backdropTop), ending: rgb(palette.backdropBottom))
    backdrop?.draw(in: NSRect(x: 0, y: 0, width: windowWidth, height: windowHeight), angle: -90)

    // Plates behind the file names Finder draws under each icon.
    if palette.labelPlateAlpha > 0 {
        let plateWidth: CGFloat = 132
        let plateHeight: CGFloat = 27
        let plateTop = iconCentreFromTop + 66
        for centreX in [appIconX, applicationsX] {
            let plate = NSBezierPath(
                roundedRect: NSRect(x: centreX - plateWidth / 2,
                                    y: windowHeight - plateTop - plateHeight,
                                    width: plateWidth, height: plateHeight),
                xRadius: 8, yRadius: 8
            )
            rgb(palette.labelPlate, alpha: palette.labelPlateAlpha).setFill()
            plate.fill()
        }
    }

    // Wordmark and tagline.
    draw(text: "Nova", font: .systemFont(ofSize: 34, weight: .semibold), color: rgb(palette.wordmark),
         centredAt: CGPoint(x: windowWidth / 2, y: windowHeight - 62))
    draw(text: "Frame-accurate video player for macOS", font: .systemFont(ofSize: 13, weight: .regular),
         color: rgb(palette.tagline), centredAt: CGPoint(x: windowWidth / 2, y: windowHeight - 92))

    // Arrow from the app to the Applications folder.
    let arrowY = windowHeight - iconCentreFromTop
    let arrowStart = appIconX + 92
    let arrowEnd = applicationsX - 92
    let shaft = NSBezierPath()
    shaft.move(to: CGPoint(x: arrowStart, y: arrowY))
    shaft.line(to: CGPoint(x: arrowEnd - 12, y: arrowY))
    shaft.lineWidth = 5
    shaft.lineCapStyle = .round
    rgb(palette.arrow, alpha: 0.55).setStroke()
    shaft.stroke()

    let head = NSBezierPath()
    head.move(to: CGPoint(x: arrowEnd - 26, y: arrowY + 13))
    head.line(to: CGPoint(x: arrowEnd, y: arrowY))
    head.line(to: CGPoint(x: arrowEnd - 26, y: arrowY - 13))
    head.lineWidth = 5
    head.lineCapStyle = .round
    head.lineJoinStyle = .round
    rgb(palette.arrow, alpha: 0.9).setStroke()
    head.stroke()

    // Instruction under the icons, clear of their file names.
    draw(text: "Drag Nova into your Applications folder", font: .systemFont(ofSize: 14, weight: .medium),
         color: rgb(palette.instruction), centredAt: CGPoint(x: windowWidth / 2, y: 92))
    draw(text: "Developed by Nadim  ·  @Nadim_404", font: .systemFont(ofSize: 11, weight: .regular),
         color: rgb(palette.credit), centredAt: CGPoint(x: windowWidth / 2, y: 40))

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
let themeName = CommandLine.arguments.count > 2 ? CommandLine.arguments[2].lowercased() : "light"
let palette = themeName == "dark" ? Palette.dark : Palette.light
print("rendering \(themeName) installer artwork")
try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
for (scale, name) in [(CGFloat(1), "background.png"), (CGFloat(2), "background@2x.png")] {
    guard let rep = renderBackground(scale: scale, palette: palette),
          let data = rep.representation(using: .png, properties: [:]) else {
        print("could not render \(name)")
        exit(1)
    }
    do {
        try data.write(to: outputDirectory.appendingPathComponent(name))
        print("wrote \(name) (\(rep.pixelsWide)x\(rep.pixelsHigh))")
    } catch {
        print("could not write \(name): \(error.localizedDescription)")
        exit(1)
    }
}
