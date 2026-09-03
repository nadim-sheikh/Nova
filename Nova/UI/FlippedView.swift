import AppKit

/// A container whose origin is its top-left corner. Used as the document view of a scroll view so
/// content laid out top-down stays anchored to the top and scrolls in the expected direction.
final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}
