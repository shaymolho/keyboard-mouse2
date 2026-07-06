import AppKit

let app = NSApplication.shared
// Top-level `let` keeps the delegate alive — NSApplication holds it weakly.
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
