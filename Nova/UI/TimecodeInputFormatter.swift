import Foundation

/// Keeps a timecode field to the characters a timecode is made of: digits and the separators
/// `:` `;` `.` `,`. Letters and anything else are refused as they are typed or pasted, so the
/// field can never hold a word. What the digits mean is still `TimecodeParser`'s decision.
final class TimecodeInputFormatter: Formatter {
    /// `00:00:00:00` is eleven characters; a little room is left for shorter separators-free entry.
    static let maximumLength = 12

    private static let separators = CharacterSet(charactersIn: ":;.,")

    static func isValid(_ text: String) -> Bool {
        guard text.count <= maximumLength else { return false }
        return text.unicodeScalars.allSatisfy { CharacterSet.decimalDigits.contains($0) || separators.contains($0) }
    }

    override func string(for obj: Any?) -> String? {
        obj as? String
    }

    override func getObjectValue(
        _ obj: AutoreleasingUnsafeMutablePointer<AnyObject?>?, for string: String,
        errorDescription error: AutoreleasingUnsafeMutablePointer<NSString?>?
    ) -> Bool {
        obj?.pointee = string as NSString
        return true
    }

    /// Returning false rejects the keystroke or paste and leaves the field's text as it was.
    override func isPartialStringValid(
        _ partialString: String, newEditingString newString: AutoreleasingUnsafeMutablePointer<NSString?>?,
        errorDescription error: AutoreleasingUnsafeMutablePointer<NSString?>?
    ) -> Bool {
        Self.isValid(partialString)
    }
}
