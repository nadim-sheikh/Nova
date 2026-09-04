import AppKit

// Nova opens its own window and never restores old ones, so AppKit's window-state restoration is
// switched off before it starts. Left on, a launch that arrives with a document to open keeps the
// window off screen for about five seconds while the app already plays: sound with no picture.
UserDefaults.standard.register(defaults: ["ApplePersistenceIgnoreState": true])

let application = NSApplication.shared
let appDelegate = AppDelegate()
application.delegate = appDelegate
_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
