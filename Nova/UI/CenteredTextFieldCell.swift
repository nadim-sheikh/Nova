import AppKit

/// A text field cell that centres its text vertically. `NSTextField` draws its text from the top
/// of the cell, so a field given a fixed height (a readout pill, say) otherwise looks off-centre.
/// The editing rects are centred too, so the text does not jump when the field is clicked into.
final class CenteredTextFieldCell: NSTextFieldCell {
    private func centered(_ rect: NSRect) -> NSRect {
        var titleRect = super.titleRect(forBounds: rect)
        let textHeight = cellSize(forBounds: rect).height
        titleRect.origin.y = rect.minY + (rect.height - textHeight) / 2
        titleRect.size.height = textHeight
        return titleRect
    }

    override func titleRect(forBounds rect: NSRect) -> NSRect {
        centered(rect)
    }

    override func drawInterior(withFrame cellFrame: NSRect, in controlView: NSView) {
        super.drawInterior(withFrame: centered(cellFrame), in: controlView)
    }

    override func edit(withFrame rect: NSRect, in controlView: NSView, editor: NSText, delegate: Any?, event: NSEvent?) {
        super.edit(withFrame: centered(rect), in: controlView, editor: editor, delegate: delegate, event: event)
    }

    override func select(withFrame rect: NSRect, in controlView: NSView, editor: NSText, delegate: Any?, start: Int, length: Int) {
        super.select(withFrame: centered(rect), in: controlView, editor: editor, delegate: delegate, start: start, length: length)
    }
}
