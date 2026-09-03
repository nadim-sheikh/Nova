import AppKit

let application = NSApplication.shared
let appDelegate = AppDelegate()
application.delegate = appDelegate
_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
