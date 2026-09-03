import Foundation

/// Every failure the player can surface to the user. Each case carries a human-readable reason.
enum PlaybackError: LocalizedError {
    case notAVideoFile(String)
    case fileNotFound(URL)
    case notPlayable
    case noVideoTrack
    case unsupportedCodec(String)
    case unknownFrameRate
    case loadFailed(underlying: Error?)
    case loadTimedOut
    case unsupportedRate(Float)
    case noMediaLoaded
    case frameCaptureFailed(underlying: Error?)
    case frameSaveFailed(underlying: Error?)
    case invalidTimecode(String)
    case noTimecodeOnClipboard

    var errorDescription: String? {
        switch self {
        case .notAVideoFile(let fileExtension):
            let subject = fileExtension.isEmpty
                ? "That file has no extension, so it can't be recognised as video"
                : "“.\(fileExtension)” isn't a video format"
            return "\(subject). Open an MP4, MOV, MKV, AVI, WebM or similar video file."
        case .fileNotFound(let url):
            return "No file exists at “\(url.path)”."
        case .notPlayable:
            return "The file isn't playable. It may be damaged, DRM-protected, or use a codec Nova can't decode."
        case .noVideoTrack:
            return "The file doesn't contain a video track."
        case .unsupportedCodec(let codec):
            return "The video is encoded with “\(codec)”, which Nova's decoder doesn't include."
        case .unknownFrameRate:
            return "The video track doesn't report a frame rate, so timecode can't be computed."
        case .loadFailed(let underlying):
            if let underlying {
                return "The file couldn't be loaded: \(underlying.localizedDescription)"
            }
            return "The file couldn't be loaded."
        case .loadTimedOut:
            return "The file took too long to open. It may be damaged or use a codec Nova can't decode."
        case .unsupportedRate(let rate):
            let direction = rate < 0 ? "reverse" : "forward"
            return "This file can't play \(direction) at \(ShuttleController.formattedMagnitude(rate))× speed."
        case .noMediaLoaded:
            return "No video is open."
        case .frameCaptureFailed(let underlying):
            if let underlying {
                return "The current frame couldn't be decoded: \(underlying.localizedDescription)"
            }
            return "The current frame couldn't be decoded."
        case .frameSaveFailed(let underlying):
            if let underlying {
                return "The frame couldn't be written: \(underlying.localizedDescription)"
            }
            return "The frame couldn't be written to that location."
        case .invalidTimecode(let text):
            return "“\(text)” isn't a timecode. Use hours:minutes:seconds:frames, for example 00:01:23:12."
        case .noTimecodeOnClipboard:
            return "The clipboard doesn't contain any text to read a timecode from."
        }
    }
}
