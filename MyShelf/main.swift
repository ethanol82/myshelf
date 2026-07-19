import Cocoa

// NSApplication.delegate는 weak — AppDelegate를 여기서 강하게 보관해야 앱 수명 동안 살아있음
let appDelegate = AppDelegate()
NSApplication.shared.delegate = appDelegate
withExtendedLifetime(appDelegate) {
    NSApplication.shared.run()
}
