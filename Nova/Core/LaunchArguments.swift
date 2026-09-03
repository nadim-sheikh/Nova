import Foundation

/// Extracts a file path passed on the command line, ignoring the `-Flag value` pairs Xcode and
/// LaunchServices inject (for example `-NSDocumentRevisionsDebugMode YES`).
enum LaunchArguments {
    static func fileURL(from arguments: [String]) -> URL? {
        var skipNext = false
        for argument in arguments.dropFirst() {
            if skipNext {
                skipNext = false
                continue
            }
            if argument.hasPrefix("-") {
                // `-psn_...` is a bare process-serial-number flag with no value.
                skipNext = !argument.hasPrefix("-psn")
                continue
            }
            return URL(fileURLWithPath: (argument as NSString).expandingTildeInPath)
        }
        return nil
    }
}
