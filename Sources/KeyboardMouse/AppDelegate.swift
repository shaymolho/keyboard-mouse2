import AppKit
import ApplicationServices

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var enabledItem: NSMenuItem!
    private let mouse = MouseController()
    private var tap: EventTap?
    private var permissionTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setUpStatusItem()

        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if AXIsProcessTrustedWithOptions(options) {
            startTap()
        } else {
            // Poll until the user grants Accessibility; the tap starts without a relaunch.
            permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
                guard AXIsProcessTrusted() else { return }
                self?.permissionTimer?.invalidate()
                self?.permissionTimer = nil
                self?.startTap()
            }
        }
    }

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(
            systemSymbolName: "cursorarrow.rays",
            accessibilityDescription: "Keyboard Mouse")

        let menu = NSMenu()
        enabledItem = NSMenuItem(title: "Enabled", action: #selector(toggleEnabled), keyEquivalent: "")
        enabledItem.target = self
        menu.addItem(enabledItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(
            title: "Quit Keyboard Mouse",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"))
        statusItem.menu = menu
        updateUI()
    }

    private func startTap() {
        let tap = EventTap(mouse: mouse)
        if tap.start() {
            self.tap = tap
            updateUI()
        } else {
            let alert = NSAlert()
            alert.messageText = "Keyboard Mouse needs Accessibility access"
            alert.informativeText = """
                Grant access in System Settings → Privacy & Security → Accessibility, \
                then relaunch the app.
                """
            alert.runModal()
        }
    }

    @objc private func toggleEnabled() {
        guard let tap else { return }
        tap.isEnabled.toggle()
        updateUI()
    }

    private func updateUI() {
        let enabled = tap?.isEnabled ?? false
        enabledItem.state = enabled ? .on : .off
        statusItem.button?.appearsDisabled = !enabled
    }
}
