import AppKit
import Libmpv
import OpenGL

/// Draws mpv's video through the libmpv OpenGL render API. mpv announces new frames from its own
/// thread; a private queue acknowledges them and asks Core Animation to redraw the layer on the
/// main thread, which also handles window resizes. `drawLock` guards the render context's lifetime.
final class MPVRenderLayer: CAOpenGLLayer {
    /// The handful of GL entry points used directly, resolved at runtime so no deprecated
    /// OpenGL headers are imported.
    private struct GLFunctions {
        typealias GetIntegerv = @convention(c) (UInt32, UnsafeMutablePointer<Int32>?) -> Void
        typealias Flush = @convention(c) () -> Void
        typealias ClearColor = @convention(c) (Float, Float, Float, Float) -> Void
        typealias Clear = @convention(c) (UInt32) -> Void
        typealias GenObjects = @convention(c) (Int32, UnsafeMutablePointer<UInt32>?) -> Void
        typealias BindObject = @convention(c) (UInt32, UInt32) -> Void
        typealias TexImage2D = @convention(c) (UInt32, Int32, Int32, Int32, Int32, Int32, UInt32, UInt32, UnsafeRawPointer?) -> Void
        typealias TexParameteri = @convention(c) (UInt32, UInt32, Int32) -> Void
        typealias FramebufferTexture2D = @convention(c) (UInt32, UInt32, UInt32, UInt32, Int32) -> Void
        typealias CheckFramebufferStatus = @convention(c) (UInt32) -> UInt32
        typealias ReadPixels = @convention(c) (Int32, Int32, Int32, Int32, UInt32, UInt32, UnsafeMutableRawPointer?) -> Void
        typealias PixelStorei = @convention(c) (UInt32, Int32) -> Void

        static let drawFramebufferBinding: UInt32 = 0x8CA6
        static let viewport: UInt32 = 0x0BA2
        static let colorBufferBit: UInt32 = 0x4000
        static let texture2D: UInt32 = 0x0DE1
        static let rgba8: Int32 = 0x8058
        static let rgba: UInt32 = 0x1908
        static let unsignedByte: UInt32 = 0x1401
        static let textureMinFilter: UInt32 = 0x2801
        static let textureMagFilter: UInt32 = 0x2800
        static let nearest: Int32 = 0x2600
        static let framebuffer: UInt32 = 0x8D40
        static let colorAttachment0: UInt32 = 0x8CE0
        static let framebufferComplete: UInt32 = 0x8CD5
        static let packAlignment: UInt32 = 0x0D05
        static let readFramebuffer: UInt32 = 0x8CA8

        let getIntegerv: GetIntegerv
        let flush: Flush
        let clearColor: ClearColor
        let clear: Clear
        let genTextures: GenObjects
        let deleteTextures: GenObjects
        let bindTexture: BindObject
        let texImage2D: TexImage2D
        let texParameteri: TexParameteri
        let genFramebuffers: GenObjects
        let deleteFramebuffers: GenObjects
        let bindFramebuffer: BindObject
        let framebufferTexture2D: FramebufferTexture2D
        let checkFramebufferStatus: CheckFramebufferStatus
        let readPixels: ReadPixels
        let pixelStorei: PixelStorei

        init?() {
            guard let library = MPVRenderLayer.openGLLibrary else { return nil }
            func load<T>(_ name: String, _ type: T.Type) -> T? {
                dlsym(library, name).map { unsafeBitCast($0, to: type) }
            }
            guard let getIntegerv = load("glGetIntegerv", GetIntegerv.self),
                  let flush = load("glFlush", Flush.self),
                  let clearColor = load("glClearColor", ClearColor.self),
                  let clear = load("glClear", Clear.self),
                  let genTextures = load("glGenTextures", GenObjects.self),
                  let deleteTextures = load("glDeleteTextures", GenObjects.self),
                  let bindTexture = load("glBindTexture", BindObject.self),
                  let texImage2D = load("glTexImage2D", TexImage2D.self),
                  let texParameteri = load("glTexParameteri", TexParameteri.self),
                  let genFramebuffers = load("glGenFramebuffers", GenObjects.self),
                  let deleteFramebuffers = load("glDeleteFramebuffers", GenObjects.self),
                  let bindFramebuffer = load("glBindFramebuffer", BindObject.self),
                  let framebufferTexture2D = load("glFramebufferTexture2D", FramebufferTexture2D.self),
                  let checkFramebufferStatus = load("glCheckFramebufferStatus", CheckFramebufferStatus.self),
                  let readPixels = load("glReadPixels", ReadPixels.self),
                  let pixelStorei = load("glPixelStorei", PixelStorei.self) else { return nil }
            self.getIntegerv = getIntegerv
            self.flush = flush
            self.clearColor = clearColor
            self.clear = clear
            self.genTextures = genTextures
            self.deleteTextures = deleteTextures
            self.bindTexture = bindTexture
            self.texImage2D = texImage2D
            self.texParameteri = texParameteri
            self.genFramebuffers = genFramebuffers
            self.deleteFramebuffers = deleteFramebuffers
            self.bindFramebuffer = bindFramebuffer
            self.framebufferTexture2D = framebufferTexture2D
            self.checkFramebufferStatus = checkFramebufferStatus
            self.readPixels = readPixels
            self.pixelStorei = pixelStorei
        }
    }

    private static let openGLLibrary = dlopen("/System/Library/Frameworks/OpenGL.framework/OpenGL", RTLD_LAZY)
    private static let gl = GLFunctions()

    private let pixelFormat: CGLPixelFormatObj?
    private let context: CGLContextObj?
    private let renderQueue = DispatchQueue(label: "com.nadimsheikh.Nova.mpv-render", qos: .userInteractive)
    private let displayLock = NSLock()
    private let drawLock = NSLock()
    private var renderContext: OpaquePointer?
    private var isAttachedToWindow = false

    override init() {
        let made = MPVRenderLayer.makeContext()
        pixelFormat = made?.pixelFormat
        context = made?.context
        super.init()
        configure()
    }

    /// Core Animation makes copies for presentation; they share the GL context but never render mpv.
    override init(layer: Any) {
        if let source = layer as? MPVRenderLayer, let format = source.pixelFormat, let context = source.context {
            pixelFormat = CGLRetainPixelFormat(format)
            self.context = CGLRetainContext(context)
        } else {
            let made = MPVRenderLayer.makeContext()
            pixelFormat = made?.pixelFormat
            context = made?.context
        }
        super.init(layer: layer)
        configure()
    }

    required init?(coder: NSCoder) {
        nil
    }

    deinit {
        if let context { CGLReleaseContext(context) }
        if let pixelFormat { CGLReleasePixelFormat(pixelFormat) }
    }

    private func configure() {
        isOpaque = true
        isAsynchronous = false
        needsDisplayOnBoundsChange = true
        backgroundColor = NSColor.black.cgColor
    }

    // MARK: - mpv render context

    /// Creates mpv's render context on this layer's GL context. Call on the main thread before
    /// loading a file, since mpv drops video output that has nowhere to go.
    func attachRenderContext(to client: MPVClient) throws {
        guard let context, let apiType = strdup("opengl") else {
            throw MPVError(code: MPV_ERROR_VO_INIT_FAILED.rawValue, operation: "Preparing OpenGL for video")
        }
        defer { free(apiType) }
        drawLock.lock()
        defer { drawLock.unlock() }
        guard renderContext == nil else { return }

        CGLSetCurrentContext(context)
        defer { CGLSetCurrentContext(nil) }

        var initParams = mpv_opengl_init_params(get_proc_address: { _, name in
            guard let name, let library = MPVRenderLayer.openGLLibrary else { return nil }
            return dlsym(library, name)
        }, get_proc_address_ctx: nil)
        var advancedControl: Int32 = 1
        var created: OpaquePointer?
        let status = withUnsafeMutablePointer(to: &initParams) { initPointer in
            withUnsafeMutablePointer(to: &advancedControl) { advancedPointer in
                var params = [
                    mpv_render_param(type: MPV_RENDER_PARAM_API_TYPE, data: UnsafeMutableRawPointer(apiType)),
                    mpv_render_param(type: MPV_RENDER_PARAM_OPENGL_INIT_PARAMS, data: UnsafeMutableRawPointer(initPointer)),
                    mpv_render_param(type: MPV_RENDER_PARAM_ADVANCED_CONTROL, data: UnsafeMutableRawPointer(advancedPointer)),
                    mpv_render_param(type: MPV_RENDER_PARAM_INVALID, data: nil),
                ]
                return mpv_render_context_create(&created, client.handle, &params)
            }
        }
        guard status >= 0, let created else {
            throw MPVError(code: status, operation: "Creating the video renderer")
        }
        renderContext = created
        mpv_render_context_set_update_callback(created, { userdata in
            guard let userdata else { return }
            let layer = Unmanaged<MPVRenderLayer>.fromOpaque(userdata).takeUnretainedValue()
            layer.renderQueue.async { layer.renderPendingFrame() }
        }, Unmanaged.passUnretained(self).toOpaque())
    }

    /// Frees the render context. Must happen before the client is destroyed, on the main thread.
    func detachRenderContext() {
        drawLock.lock()
        guard let renderContext else {
            drawLock.unlock()
            return
        }
        mpv_render_context_set_update_callback(renderContext, nil, nil)
        self.renderContext = nil
        drawLock.unlock()
        // Released the lock first: a queued render may be waiting to draw, and would deadlock otherwise.
        renderQueue.sync {}
        CGLSetCurrentContext(context)
        mpv_render_context_free(renderContext)
        CGLSetCurrentContext(nil)
    }

    /// Renders the frame currently on screen into an offscreen framebuffer of the given pixel size
    /// and reads it back. Works for every decoding mode, including zero-copy hardware frames that
    /// mpv's own screenshot commands cannot read, and matches the on-screen colour conversion.
    func captureFrame(width: Int, height: Int) -> CGImage? {
        guard let gl = MPVRenderLayer.gl, let context, width > 0, height > 0 else { return nil }
        drawLock.lock()
        defer { drawLock.unlock() }
        guard let renderContext else { return nil }
        CGLSetCurrentContext(context)
        defer { CGLSetCurrentContext(nil) }

        var texture: UInt32 = 0
        var framebuffer: UInt32 = 0
        gl.genTextures(1, &texture)
        gl.genFramebuffers(1, &framebuffer)
        defer {
            gl.bindFramebuffer(GLFunctions.framebuffer, 0)
            gl.deleteFramebuffers(1, &framebuffer)
            gl.deleteTextures(1, &texture)
        }
        gl.bindTexture(GLFunctions.texture2D, texture)
        gl.texImage2D(GLFunctions.texture2D, 0, GLFunctions.rgba8, Int32(width), Int32(height), 0, GLFunctions.rgba, GLFunctions.unsignedByte, nil)
        gl.texParameteri(GLFunctions.texture2D, GLFunctions.textureMinFilter, GLFunctions.nearest)
        gl.texParameteri(GLFunctions.texture2D, GLFunctions.textureMagFilter, GLFunctions.nearest)
        gl.bindFramebuffer(GLFunctions.framebuffer, framebuffer)
        gl.framebufferTexture2D(GLFunctions.framebuffer, GLFunctions.colorAttachment0, GLFunctions.texture2D, texture, 0)
        guard gl.checkFramebufferStatus(GLFunctions.framebuffer) == GLFunctions.framebufferComplete else { return nil }

        var target = mpv_opengl_fbo(fbo: Int32(framebuffer), w: Int32(width), h: Int32(height), internal_format: 0)
        // Unflipped: glReadPixels returns rows bottom-up, which turns mpv's normal output top-first.
        var flipY: Int32 = 0
        var noWait: Int32 = 0
        let status = withUnsafeMutablePointer(to: &target) { targetPointer in
            withUnsafeMutablePointer(to: &flipY) { flipPointer in
                withUnsafeMutablePointer(to: &noWait) { waitPointer in
                    var params = [
                        mpv_render_param(type: MPV_RENDER_PARAM_OPENGL_FBO, data: UnsafeMutableRawPointer(targetPointer)),
                        mpv_render_param(type: MPV_RENDER_PARAM_FLIP_Y, data: UnsafeMutableRawPointer(flipPointer)),
                        mpv_render_param(type: MPV_RENDER_PARAM_BLOCK_FOR_TARGET_TIME, data: UnsafeMutableRawPointer(waitPointer)),
                        mpv_render_param(type: MPV_RENDER_PARAM_INVALID, data: nil),
                    ]
                    return mpv_render_context_render(renderContext, &params)
                }
            }
        }
        guard status >= 0 else { return nil }

        // mpv leaves its own framebuffers bound; read back from ours explicitly.
        gl.bindFramebuffer(GLFunctions.readFramebuffer, framebuffer)
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
        gl.pixelStorei(GLFunctions.packAlignment, 1)
        pixels.withUnsafeMutableBytes { buffer in
            gl.readPixels(0, 0, Int32(width), Int32(height), GLFunctions.rgba, GLFunctions.unsignedByte, buffer.baseAddress)
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        return CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        )
    }

    /// While detached from a window, frames are acknowledged without drawing so playback keeps time.
    func setAttachedToWindow(_ attached: Bool) {
        drawLock.lock()
        isAttachedToWindow = attached
        drawLock.unlock()
    }

    private func renderPendingFrame() {
        drawLock.lock()
        guard let renderContext else {
            drawLock.unlock()
            return
        }
        // With advanced control, the update call itself may run GL work (frame captures, for
        // one), so the context has to be current here and not only inside `draw`.
        CGLSetCurrentContext(context)
        let flags = mpv_render_context_update(renderContext)
        let hasFrame = flags & UInt64(MPV_RENDER_UPDATE_FRAME.rawValue) != 0
        let canDraw = isAttachedToWindow
        if hasFrame, !canDraw {
            skipFrame(renderContext)
        }
        CGLSetCurrentContext(nil)
        drawLock.unlock()
        guard hasFrame, canDraw else { return }
        // Drawing at the next Core Animation commit keeps memory flat and costs less CPU than
        // presenting from this queue; mpv paces its video thread to our render calls either way.
        DispatchQueue.main.async { [self] in setNeedsDisplay() }
    }

    /// Consumes a frame without drawing it. The GL context is already current.
    private func skipFrame(_ renderContext: OpaquePointer) {
        var skip: Int32 = 1
        withUnsafeMutablePointer(to: &skip) { skipPointer in
            var params = [
                mpv_render_param(type: MPV_RENDER_PARAM_SKIP_RENDERING, data: UnsafeMutableRawPointer(skipPointer)),
                mpv_render_param(type: MPV_RENDER_PARAM_INVALID, data: nil),
            ]
            mpv_render_context_render(renderContext, &params)
        }
    }

    // MARK: - CAOpenGLLayer

    override func copyCGLPixelFormat(forDisplayMask mask: UInt32) -> CGLPixelFormatObj {
        guard let pixelFormat else { return super.copyCGLPixelFormat(forDisplayMask: mask) }
        return CGLRetainPixelFormat(pixelFormat)
    }

    override func copyCGLContext(forPixelFormat pixelFormat: CGLPixelFormatObj) -> CGLContextObj {
        guard let context else { return super.copyCGLContext(forPixelFormat: pixelFormat) }
        return CGLRetainContext(context)
    }

    override func canDraw(
        inCGLContext ctx: CGLContextObj, pixelFormat pf: CGLPixelFormatObj,
        forLayerTime t: CFTimeInterval, displayTime ts: UnsafePointer<CVTimeStamp>?
    ) -> Bool {
        true
    }

    override func display() {
        displayLock.lock()
        super.display()
        displayLock.unlock()
    }

    override func draw(
        inCGLContext ctx: CGLContextObj, pixelFormat pf: CGLPixelFormatObj,
        forLayerTime t: CFTimeInterval, displayTime ts: UnsafePointer<CVTimeStamp>?
    ) {
        guard let gl = MPVRenderLayer.gl else { return }
        drawLock.lock()
        defer { drawLock.unlock() }
        guard let renderContext else {
            gl.clearColor(0, 0, 0, 1)
            gl.clear(GLFunctions.colorBufferBit)
            gl.flush()
            return
        }

        // Core Animation hands us a framebuffer of its own, sized to the layer in pixels.
        var framebuffer: Int32 = 0
        gl.getIntegerv(GLFunctions.drawFramebufferBinding, &framebuffer)
        var viewport: [Int32] = [0, 0, 0, 0]
        gl.getIntegerv(GLFunctions.viewport, &viewport)
        guard viewport[2] > 0, viewport[3] > 0 else { return }

        var target = mpv_opengl_fbo(fbo: framebuffer, w: viewport[2], h: viewport[3], internal_format: 0)
        var flipY: Int32 = 1
        withUnsafeMutablePointer(to: &target) { targetPointer in
            withUnsafeMutablePointer(to: &flipY) { flipPointer in
                var params = [
                    mpv_render_param(type: MPV_RENDER_PARAM_OPENGL_FBO, data: UnsafeMutableRawPointer(targetPointer)),
                    mpv_render_param(type: MPV_RENDER_PARAM_FLIP_Y, data: UnsafeMutableRawPointer(flipPointer)),
                    mpv_render_param(type: MPV_RENDER_PARAM_INVALID, data: nil),
                ]
                mpv_render_context_render(renderContext, &params)
            }
        }
        gl.flush()
    }

    // MARK: - GL context

    private static func makeContext() -> (pixelFormat: CGLPixelFormatObj, context: CGLContextObj)? {
        let coreProfile = CGLPixelFormatAttribute(kCGLOGLPVersion_3_2_Core.rawValue)
        let candidates: [[CGLPixelFormatAttribute]] = [
            [kCGLPFADoubleBuffer, kCGLPFAAllowOfflineRenderers, kCGLPFAAccelerated, kCGLPFAOpenGLProfile, coreProfile, CGLPixelFormatAttribute(0)],
            // Some virtual machines have no accelerated renderer.
            [kCGLPFADoubleBuffer, kCGLPFAAllowOfflineRenderers, kCGLPFAOpenGLProfile, coreProfile, CGLPixelFormatAttribute(0)],
        ]
        for attributes in candidates {
            var pixelFormat: CGLPixelFormatObj?
            var count: GLint = 0
            guard CGLChoosePixelFormat(attributes, &pixelFormat, &count) == kCGLNoError, let pixelFormat else { continue }
            var context: CGLContextObj?
            guard CGLCreateContext(pixelFormat, nil, &context) == kCGLNoError, let context else {
                CGLReleasePixelFormat(pixelFormat)
                continue
            }
            return (pixelFormat, context)
        }
        return nil
    }
}
