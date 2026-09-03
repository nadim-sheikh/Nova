import AppKit

/// Shows the standard macOS About panel with the developer credit and a clickable link.
enum AboutPanel {
    static func show() {
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits()])
    }

    private static func credits() -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let base: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph,
        ]
        let text = NSMutableAttributedString(string: "Developed by \(DeveloperCredits.developerName)\n", attributes: base)
        var linkAttributes = base
        if let url = DeveloperCredits.xProfileURL {
            linkAttributes[.link] = url
        }
        text.append(NSAttributedString(string: "\(DeveloperCredits.xHandle) on X", attributes: linkAttributes))
        return text
    }
}
