import Foundation
import Libmpv

/// Thread-safe wrapper around one `mpv_handle`: options, commands, properties, and an event pump
/// that hands mpv's events to the main queue. Knows nothing about `PlaybackEngine`.
final class MPVClient: @unchecked Sendable {
    enum PropertyValue: Equatable {
        case double(Double)
        case flag(Bool)
        case int64(Int64)
        case string(String)
        case unavailable
    }

    enum Event {
        case fileLoaded
        /// `error` is an mpv error code when loading or decoding failed, nil for a normal end or stop.
        case endOfFile(error: Int32?)
        case playbackRestarted
        case propertyChanged(name: String, value: PropertyValue)
        case shutdown
    }

    /// One decoded frame as packed 32-bit pixels.
    struct RawFrame {
        let width: Int
        let height: Int
        let stride: Int
        /// mpv's pixel format name: `bgr0`, `bgra`, `rgba` or `rgb0`.
        let format: String
        let data: Data
    }

    let handle: OpaquePointer
    /// Called on the main queue for every event mpv emits.
    var onEvent: ((Event) -> Void)?

    private let eventQueue = DispatchQueue(label: "com.nadimsheikh.Nova.mpv-events")
    private let stateLock = NSLock()
    private var isDestroyed = false

    init() throws {
        guard let handle = mpv_create() else {
            throw MPVError(code: MPV_ERROR_NOMEM.rawValue, operation: "Creating the mpv player")
        }
        self.handle = handle
    }

    // MARK: - Lifecycle

    /// Options must be set before `initialize()`. Options for components this libmpv build
    /// doesn't include simply don't exist, so those are skipped rather than treated as failures.
    func setOption(_ name: String, _ value: String) throws {
        let status = mpv_set_option_string(handle, name, value)
        guard status != MPV_ERROR_OPTION_NOT_FOUND.rawValue else { return }
        try check(status, "Setting mpv option \(name)")
    }

    /// Starts the player core and begins delivering events.
    func initialize() throws {
        try check(mpv_initialize(handle), "Starting the mpv player")
        mpv_set_wakeup_callback(handle, { context in
            guard let context else { return }
            let client = Unmanaged<MPVClient>.fromOpaque(context).takeUnretainedValue()
            client.eventQueue.async { client.drainEvents() }
        }, Unmanaged.passUnretained(self).toOpaque())
    }

    /// Tears the player down. Any render context must have been freed first.
    func destroy() {
        stateLock.lock()
        let alreadyDestroyed = isDestroyed
        isDestroyed = true
        stateLock.unlock()
        guard !alreadyDestroyed else { return }
        mpv_set_wakeup_callback(handle, nil, nil)
        // Let an in-flight drain finish so nothing touches the handle after it is gone.
        eventQueue.sync {}
        mpv_terminate_destroy(handle)
    }

    // MARK: - Commands

    func command(_ args: [String]) throws {
        try check(run(args), "Command “\(args.first ?? "")”")
    }

    /// Runs a command and returns mpv's status code (negative on failure) instead of throwing.
    @discardableResult
    func run(_ args: [String]) -> Int32 {
        var argv: [UnsafeMutablePointer<CChar>?] = args.map { strdup($0) }
        argv.append(nil)
        defer { argv.forEach { free($0) } }
        return argv.withUnsafeMutableBufferPointer { buffer in
            buffer.withMemoryRebound(to: UnsafePointer<CChar>?.self) { mpv_command(handle, $0.baseAddress) }
        }
    }

    /// The frame on screen at full resolution, without on-screen display or subtitles.
    func rawScreenshot() throws -> RawFrame {
        var result = mpv_node()
        // Older cores don't take the format argument; fall back to their default `bgr0`.
        var status = withNodeArray(["screenshot-raw", "video", "bgra"]) { mpv_command_node(handle, $0, &result) }
        if status < 0 {
            status = withNodeArray(["screenshot-raw", "video"]) { mpv_command_node(handle, $0, &result) }
        }
        try check(status, "Capturing the frame")
        defer { mpv_free_node_contents(&result) }
        return try frame(from: result)
    }

    // MARK: - Properties

    func setProperty(_ name: String, double value: Double) throws {
        var value = value
        try check(mpv_set_property(handle, name, MPV_FORMAT_DOUBLE, &value), "Setting \(name)")
    }

    func setProperty(_ name: String, flag value: Bool) throws {
        var value: Int32 = value ? 1 : 0
        try check(mpv_set_property(handle, name, MPV_FORMAT_FLAG, &value), "Setting \(name)")
    }

    func setProperty(_ name: String, string value: String) throws {
        try check(mpv_set_property_string(handle, name, value), "Setting \(name)")
    }

    /// nil when the property has no value yet (for example before a file is loaded).
    func double(_ name: String) -> Double? {
        var value = 0.0
        return mpv_get_property(handle, name, MPV_FORMAT_DOUBLE, &value) >= 0 ? value : nil
    }

    func flag(_ name: String) -> Bool? {
        var value: Int32 = 0
        return mpv_get_property(handle, name, MPV_FORMAT_FLAG, &value) >= 0 ? value != 0 : nil
    }

    func int(_ name: String) -> Int64? {
        var value: Int64 = 0
        return mpv_get_property(handle, name, MPV_FORMAT_INT64, &value) >= 0 ? value : nil
    }

    func string(_ name: String) -> String? {
        var value: UnsafeMutablePointer<CChar>?
        guard mpv_get_property(handle, name, MPV_FORMAT_STRING, &value) >= 0, let value else { return nil }
        defer { mpv_free(value) }
        return String(cString: value)
    }

    /// Requests `.propertyChanged` events whenever the property changes.
    func observe(_ name: String, format: mpv_format) {
        mpv_observe_property(handle, 0, name, format)
    }

    // MARK: - Events

    private func drainEvents() {
        stateLock.lock()
        let destroyed = isDestroyed
        stateLock.unlock()
        guard !destroyed else { return }

        while let event = mpv_wait_event(handle, 0), event.pointee.event_id != MPV_EVENT_NONE {
            if let translated = translate(event.pointee) {
                DispatchQueue.main.async { [self] in onEvent?(translated) }
            }
            if event.pointee.event_id == MPV_EVENT_SHUTDOWN { return }
        }
    }

    private func translate(_ event: mpv_event) -> Event? {
        switch event.event_id {
        case MPV_EVENT_FILE_LOADED:
            return .fileLoaded
        case MPV_EVENT_END_FILE:
            guard let data = event.data?.assumingMemoryBound(to: mpv_event_end_file.self) else {
                return .endOfFile(error: nil)
            }
            let info = data.pointee
            return .endOfFile(error: info.reason == MPV_END_FILE_REASON_ERROR ? info.error : nil)
        case MPV_EVENT_PLAYBACK_RESTART:
            return .playbackRestarted
        case MPV_EVENT_PROPERTY_CHANGE:
            guard let data = event.data?.assumingMemoryBound(to: mpv_event_property.self) else { return nil }
            let property = data.pointee
            return .propertyChanged(name: String(cString: property.name), value: value(of: property))
        case MPV_EVENT_SHUTDOWN:
            return .shutdown
        default:
            return nil
        }
    }

    private func value(of property: mpv_event_property) -> PropertyValue {
        guard let data = property.data else { return .unavailable }
        switch property.format {
        case MPV_FORMAT_DOUBLE:
            return .double(data.assumingMemoryBound(to: Double.self).pointee)
        case MPV_FORMAT_FLAG:
            return .flag(data.assumingMemoryBound(to: Int32.self).pointee != 0)
        case MPV_FORMAT_INT64:
            return .int64(data.assumingMemoryBound(to: Int64.self).pointee)
        case MPV_FORMAT_STRING:
            guard let cString = data.assumingMemoryBound(to: UnsafePointer<CChar>?.self).pointee else {
                return .unavailable
            }
            return .string(String(cString: cString))
        default:
            return .unavailable
        }
    }

    // MARK: - Node plumbing

    /// Builds an mpv string-array node for `body`, freeing it afterwards.
    private func withNodeArray(_ strings: [String], _ body: (UnsafeMutablePointer<mpv_node>) -> Int32) -> Int32 {
        let cStrings = strings.map { strdup($0) }
        defer { cStrings.forEach { free($0) } }
        var nodes = cStrings.map { cString -> mpv_node in
            var node = mpv_node()
            node.format = MPV_FORMAT_STRING
            node.u.string = cString
            return node
        }
        return nodes.withUnsafeMutableBufferPointer { buffer in
            var list = mpv_node_list(num: Int32(buffer.count), values: buffer.baseAddress, keys: nil)
            return withUnsafeMutablePointer(to: &list) { listPointer in
                var array = mpv_node()
                array.format = MPV_FORMAT_NODE_ARRAY
                array.u.list = listPointer
                return withUnsafeMutablePointer(to: &array, body)
            }
        }
    }

    private func frame(from node: mpv_node) throws -> RawFrame {
        let malformed = MPVError(code: MPV_ERROR_PROPERTY_FORMAT.rawValue, operation: "Reading the captured frame")
        guard node.format == MPV_FORMAT_NODE_MAP, let list = node.u.list?.pointee else { throw malformed }

        var width = 0, height = 0, stride = 0
        var format = ""
        var data: Data?
        for index in 0..<Int(list.num) {
            guard let key = list.keys[index] else { continue }
            let value = list.values[index]
            switch String(cString: key) {
            case "w": width = Int(value.u.int64)
            case "h": height = Int(value.u.int64)
            case "stride": stride = Int(value.u.int64)
            case "format": format = value.u.string.map { String(cString: $0) } ?? ""
            case "data":
                if let byteArray = value.u.ba?.pointee, let bytes = byteArray.data {
                    data = Data(bytes: bytes, count: byteArray.size)
                }
            default: break
            }
        }
        guard width > 0, height > 0, stride > 0, let data, data.count >= stride * height else { throw malformed }
        return RawFrame(width: width, height: height, stride: stride, format: format, data: data)
    }

    private func check(_ status: Int32, _ operation: String) throws {
        guard status >= 0 else { throw MPVError(code: status, operation: operation) }
    }
}
