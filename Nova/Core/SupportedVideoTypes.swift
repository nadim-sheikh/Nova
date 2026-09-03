import Foundation
import UniformTypeIdentifiers

/// Classifies files for the open flow. Which formats can actually be *decoded* is the engine's
/// business (see `PlaybackEngine.supportedContentTypes`); this only recognises video files.
enum SupportedVideoTypes {
    /// True when macOS classifies the file as video, or its extension is one the engine accepts.
    /// The second check matters for containers macOS has no type for, such as MKV on a clean Mac.
    static func isVideoFile(_ url: URL, acceptedTypes: [UTType]) -> Bool {
        if let type = contentType(of: url), type.conforms(to: .movie) || type.conforms(to: .video) {
            return true
        }
        let fileExtension = url.pathExtension.lowercased()
        guard !fileExtension.isEmpty else { return false }
        return acceptedTypes.contains { type in
            type.tags[.filenameExtension]?.contains(fileExtension) == true
        }
    }

    static func contentType(of url: URL) -> UTType? {
        if let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType {
            return type
        }
        return UTType(filenameExtension: url.pathExtension.lowercased())
    }
}
