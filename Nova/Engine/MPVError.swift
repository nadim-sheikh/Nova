import Foundation
import Libmpv

/// A failed libmpv call, described with mpv's own wording for the error code.
struct MPVError: LocalizedError {
    let code: Int32
    let operation: String

    var errorDescription: String? {
        "\(operation): \(String(cString: mpv_error_string(code)))."
    }
}
