import CoreGraphics
import Foundation

// C callback: cannot capture context, so `self` travels through userInfo.
private func eventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let tap = Unmanaged<EventTap>.fromOpaque(userInfo).takeUnretainedValue()

    // macOS disables taps that respond too slowly or across sleep/wake.
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        tap.reEnableTap()
        return Unmanaged.passUnretained(event)
    }
    return tap.handle(type: type, event: event)
}

final class EventTap {
    private enum Key {
        static let left: Int64 = 123
        static let right: Int64 = 124
        static let down: Int64 = 125
        static let up: Int64 = 126
        static let s: Int64 = 1
        static let a: Int64 = 0
    }

    private let mouse: MouseController
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    // Keycodes whose keyDown we swallowed — their keyUp must be swallowed too,
    // even if the modifiers were released in between.
    private var suppressedKeys: Set<Int64> = []

    var isEnabled = true {
        didSet {
            guard isEnabled != oldValue, let tap else { return }
            CGEvent.tapEnable(tap: tap, enable: isEnabled)
            if !isEnabled {
                mouse.stopAll()
                suppressedKeys.removeAll()
            }
        }
    }

    init(mouse: MouseController) {
        self.mouse = mouse
    }

    /// Returns false when the tap can't be created (Accessibility not granted).
    func start() -> Bool {
        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: eventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }

        self.tap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func reEnableTap() {
        guard isEnabled, let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    /// Returns nil to suppress the event, or the event itself to pass it through.
    func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        guard isEnabled else { return Unmanaged.passUnretained(event) }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

        switch type {
        case .keyDown:
            guard hotkeyModifiersDown(event.flags) else { break }
            let action: (() -> Void)?
            switch keyCode {
            case Key.s:
                action = { self.mouse.click(.left) }
            case Key.a:
                action = { self.mouse.click(.right) }
            default:
                guard let dir = direction(for: keyCode) else { action = nil; break }
                action = { self.mouse.arrowPressed(dir) }
            }
            guard let action else { break }
            // Auto-repeats are swallowed but ignored: the timer drives movement,
            // and holding S/A must not machine-gun clicks.
            let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            if !isRepeat { action() }
            suppressedKeys.insert(keyCode)
            return nil

        case .keyUp:
            if suppressedKeys.remove(keyCode) != nil {
                if let dir = direction(for: keyCode) {
                    mouse.arrowReleased(dir)
                }
                return nil
            }

        case .flagsChanged:
            // Never suppress modifier transitions. If ctrl/option was released
            // mid-move, stop immediately; suppressedKeys stays intact so each
            // pending keyUp is still swallowed individually.
            if !hotkeyModifiersDown(event.flags) {
                mouse.stopAll()
            }

        default:
            break
        }
        return Unmanaged.passUnretained(event)
    }

    private func hotkeyModifiersDown(_ flags: CGEventFlags) -> Bool {
        // Command excluded so ctrl+opt+cmd system shortcuts keep working;
        // lenient about Shift.
        flags.contains(.maskControl)
            && flags.contains(.maskAlternate)
            && !flags.contains(.maskCommand)
    }

    private func direction(for keyCode: Int64) -> MouseController.Direction? {
        switch keyCode {
        case Key.left: return .left
        case Key.right: return .right
        case Key.down: return .down
        case Key.up: return .up
        default: return nil
        }
    }
}
