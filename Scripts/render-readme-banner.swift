// Renders assets/banner.png for the README: the app icon beside the wordmark and tagline on a
// dark plate, at 2x so it stays crisp on Retina displays at its 700 pt display width.
//   swift Scripts/render-readme-banner.swift <iconPNG> <outputPNG>
import AppKit

let arguments = CommandLine.arguments
guard arguments.count == 3, let icon = NSImage(contentsOfFile: arguments[1]) else {
    FileHandle.standardError.write(Data("usage: render-readme-banner.swift <icon.png> <banner.png>\n".utf8))
    exit(1)
}
let scale: CGFloat = 2
let size = NSSize(width: 700 * scale, height: 210 * scale)
let image = NSImage(size: size)
image.lockFocus()
let rect = NSRect(origin: .zero, size: size)
NSColor(calibratedRed: 0.075, green: 0.078, blue: 0.09, alpha: 1).setFill()
NSBezierPath(roundedRect: rect, xRadius: 28 * scale, yRadius: 28 * scale).fill()
let glow = NSGradient(colors: [NSColor(calibratedRed: 0.2, green: 0.55, blue: 1, alpha: 0.28), NSColor(calibratedWhite: 0, alpha: 0)])
glow?.draw(in: NSRect(x: -60 * scale, y: -80 * scale, width: 420 * scale, height: 380 * scale), relativeCenterPosition: NSPoint(x: -0.4, y: 0.2))

let iconSide = 128 * scale
let iconRect = NSRect(x: 60 * scale, y: (size.height - iconSide) / 2, width: iconSide, height: iconSide)
icon.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: 1)

func draw(_ text: String, size fontSize: CGFloat, weight: NSFont.Weight, color: NSColor, at point: NSPoint) {
    let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: fontSize * scale, weight: weight), .foregroundColor: color]
    (text as NSString).draw(at: NSPoint(x: point.x * scale, y: point.y * scale), withAttributes: attributes)
}
draw("Nova", size: 54, weight: .bold, color: .white, at: NSPoint(x: 222, y: 96))
draw("Frame-accurate video player for macOS", size: 20, weight: .medium, color: NSColor(calibratedWhite: 0.85, alpha: 1), at: NSPoint(x: 224, y: 62))
draw("Every codec  ·  SMPTE timecode  ·  JKL shuttle  ·  Precision timeline", size: 14, weight: .regular, color: NSColor(calibratedWhite: 0.6, alpha: 1), at: NSPoint(x: 224, y: 38))
image.unlockFocus()

guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) else { exit(2) }
try? png.write(to: URL(fileURLWithPath: arguments[2]))
print("wrote \(arguments[2]) \(Int(size.width))x\(Int(size.height))")
