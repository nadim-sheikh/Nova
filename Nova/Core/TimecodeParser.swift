import Foundation

/// Turns pasted or typed text into a `Timecode` at a given frame rate.
/// Pure value type: no AppKit, no AVFoundation.
///
/// Accepted forms, all read from the right like an NLE's timecode field:
/// - Full SMPTE `HH:MM:SS:FF` or drop-frame `HH:MM:SS;FF`
/// - Shorter fields `MM:SS:FF` and `SS:FF` (missing leading fields are zero)
/// - Bare digits `HHMMSSFF`, so `12315` means 00:01:23:15
/// Separators may be `:`, `;`, `.` or `,`. Surrounding text such as a copied window title is ignored.
enum TimecodeParser {
    static func parse(_ text: String, frameRate: Double) -> Timecode? {
        guard frameRate > 0, let fields = fields(in: text), fields.count <= 4 else { return nil }
        let padded = Array(repeating: 0, count: 4 - fields.count) + fields
        return timecode(hours: padded[0], minutes: padded[1], seconds: padded[2], frames: padded[3], frameRate: frameRate)
    }

    /// Splits the first timecode-looking run of the text into integer fields, frames last.
    private static func fields(in text: String) -> [Int]? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Two to four fields, not part of a longer run of digits or fields.
        let separated = #"(?<![\d:;.,])\d{1,2}(?:[:;.,]\d{1,2}){1,3}(?![:;.,]?\d)"#
        if let range = trimmed.range(of: separated, options: .regularExpression) {
            return trimmed[range]
                .split(whereSeparator: { ":;.,".contains($0) })
                .compactMap { Int($0) }
        }

        // No separators: read the digits as pairs from the right (FF, then SS, MM, HH).
        guard trimmed.allSatisfy(\.isNumber), trimmed.count <= 8 else { return nil }
        var digits = Substring(trimmed)
        var fields: [Int] = []
        while !digits.isEmpty {
            let pair = digits.suffix(2)
            guard let value = Int(pair) else { return nil }
            fields.insert(value, at: 0)
            digits = digits.dropLast(pair.count)
        }
        return fields
    }

    private static func timecode(hours: Int, minutes: Int, seconds: Int, frames: Int, frameRate: Double) -> Timecode? {
        let nominal = Timecode.nominalRate(frameRate: frameRate)
        guard hours < 24, minutes < 60, seconds < 60, frames < nominal else { return nil }

        let dropFrame = Timecode.isDropFrame(frameRate: frameRate)
        var frames = frames
        if dropFrame, seconds == 0, minutes % 10 != 0 {
            // Drop-frame skips the first frame numbers of every minute except each tenth one, so
            // e.g. 00:01:00;00 and ;01 don't exist at 29.97. Snap to the first real frame of that minute.
            let dropCount = Int((frameRate * 0.066666).rounded())
            frames = max(frames, dropCount)
        }
        return Timecode(hours: hours, minutes: minutes, seconds: seconds, frames: frames, isDropFrame: dropFrame)
    }
}
