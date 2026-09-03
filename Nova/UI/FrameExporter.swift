import AppKit
import UniformTypeIdentifiers

/// Encodes a captured frame for writing to disk and suggests a file name for it.
enum FrameExporter {
    /// Formats offered in the save dialog; the first is the default.
    static let contentTypes: [UTType] = [.png, .jpeg, .tiff]

    static func suggestedFileName(videoName: String?, frameNumber: Int) -> String {
        let base = videoName.map { ($0 as NSString).deletingPathExtension } ?? ""
        guard !base.isEmpty else { return "Frame \(frameNumber).png" }
        return "\(base) frame \(frameNumber).png"
    }

    /// Encodes for the extension the user chose, falling back to PNG for anything unrecognised.
    static func data(for image: CGImage, fileExtension: String) -> Data? {
        let bitmap = NSBitmapImageRep(cgImage: image)
        guard let type = UTType(filenameExtension: fileExtension.lowercased()) else {
            return bitmap.representation(using: .png, properties: [:])
        }
        if type.conforms(to: .jpeg) {
            return bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.95])
        }
        if type.conforms(to: .tiff) {
            return bitmap.tiffRepresentation
        }
        return bitmap.representation(using: .png, properties: [:])
    }
}
