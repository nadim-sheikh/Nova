import AppKit

/// Layer-hosting view for `MPVRenderLayer`, keeping the layer's pixel scale in step with the screen.
final class MPVRenderView: NSView {
    let renderLayer = MPVRenderLayer()

    init() {
        super.init(frame: .zero)
        layer = renderLayer
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var isOpaque: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateContentsScale()
        renderLayer.setAttachedToWindow(window != nil)
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateContentsScale()
    }

    private func updateContentsScale() {
        guard let scale = window?.backingScaleFactor else { return }
        renderLayer.contentsScale = scale
    }
}
