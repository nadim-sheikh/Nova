import Foundation

/// SMPTE timecode for a frame index at a given frame rate.
/// Pure value type: no AppKit, no AVFoundation.
struct Timecode: Equatable {
    let hours: Int
    let minutes: Int
    let seconds: Int
    let frames: Int
    let isDropFrame: Bool

    /// Drop-frame counting only applies to the NTSC rates 29.97 and 59.94.
    static func isDropFrame(frameRate: Double) -> Bool {
        abs(frameRate - 29.97) < 0.01 || abs(frameRate - 59.94) < 0.01
    }

    /// The integer rate used for counting frames per second (29.97 -> 30, 23.976 -> 24).
    static func nominalRate(frameRate: Double) -> Int {
        max(1, Int(frameRate.rounded()))
    }

    /// Absolute frame index (0-based) for a time in seconds.
    static func frameCount(seconds: Double, frameRate: Double) -> Int {
        guard seconds.isFinite, frameRate > 0 else { return 0 }
        // Times that land exactly on a frame boundary can round to n.9999...; nudge before flooring.
        return max(0, Int((seconds * frameRate + 1e-6).rounded(.down)))
    }

    /// Time in seconds for an absolute frame index.
    static func seconds(frameCount: Int, frameRate: Double) -> Double {
        guard frameRate > 0 else { return 0 }
        return Double(frameCount) / frameRate
    }

    /// A time safely inside the given frame, for seeking. Seeking to the frame's exact start can
    /// land a rounding error before the boundary and show the previous frame instead.
    static func midFrameSeconds(frameCount: Int, frameRate: Double) -> Double {
        guard frameRate > 0 else { return 0 }
        return (Double(frameCount) + 0.5) / frameRate
    }

    init(hours: Int, minutes: Int, seconds: Int, frames: Int, isDropFrame: Bool) {
        self.hours = hours
        self.minutes = minutes
        self.seconds = seconds
        self.frames = frames
        self.isDropFrame = isDropFrame
    }

    init(frameCount: Int, frameRate: Double) {
        let nominal = Timecode.nominalRate(frameRate: frameRate)
        let dropFrame = Timecode.isDropFrame(frameRate: frameRate)
        var frame = max(0, frameCount)

        if dropFrame {
            // Drop-frame timecode skips the first `dropCount` frame *numbers* of every minute,
            // except every tenth minute, so the displayed time tracks wall-clock time at
            // 29.97/59.94 fps. Convert the true frame index into the "labelled" index by
            // adding back the skipped numbers for every full minute/ten-minute block passed.
            let dropCount = Int((frameRate * 0.066666).rounded())          // 2 at 29.97, 4 at 59.94
            let framesPerTenMinutes = Int((frameRate * 600).rounded())     // 17982 at 29.97
            let framesPerMinute = nominal * 60 - dropCount                  // 1798 at 29.97
            let tenMinuteBlocks = frame / framesPerTenMinutes
            let remainder = frame % framesPerTenMinutes

            frame += dropCount * 9 * tenMinuteBlocks
            if remainder > dropCount {
                frame += dropCount * ((remainder - dropCount) / framesPerMinute)
            }
        }

        frames = frame % nominal
        seconds = (frame / nominal) % 60
        minutes = (frame / nominal / 60) % 60
        hours = (frame / nominal / 3600) % 24
        isDropFrame = dropFrame
    }

    init(seconds: Double, frameRate: Double) {
        self.init(frameCount: Timecode.frameCount(seconds: seconds, frameRate: frameRate), frameRate: frameRate)
    }

    /// Absolute frame index this timecode labels at the given frame rate (inverse of `init(frameCount:frameRate:)`).
    func frameCount(frameRate: Double) -> Int {
        let nominal = Timecode.nominalRate(frameRate: frameRate)
        let totalMinutes = hours * 60 + minutes
        var count = (totalMinutes * 60 + seconds) * nominal + frames
        if isDropFrame {
            let dropCount = Int((frameRate * 0.066666).rounded())
            count -= dropCount * (totalMinutes - totalMinutes / 10)
        }
        return max(0, count)
    }

    /// `HH:MM:SS:FF` for non-drop-frame, `HH:MM:SS;FF` for drop-frame.
    var smpteString: String {
        let separator = isDropFrame ? ";" : ":"
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds) + separator + String(format: "%02d", frames)
    }
}
