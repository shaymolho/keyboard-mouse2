import CoreGraphics
import Foundation

final class MouseController {
    enum Direction {
        case up, down, left, right
    }

    enum Button {
        case left, right
    }

    private let minSpeed: CGFloat = 250 // px/s
    private let maxSpeed: CGFloat = 3000 // px/s
    private let rampDuration: TimeInterval = 0.8

    private var heldDirections: Set<Direction> = []
    private var timer: Timer?
    private var rampStart: Date?
    private var lastTick: Date?
    // Fractional accumulator: at min speed a 60Hz tick moves 2.5px,
    // so sub-pixel remainders must carry over between ticks.
    private var pos: CGPoint = .zero

    func arrowPressed(_ direction: Direction) {
        heldDirections.insert(direction)
        guard timer == nil else { return }
        pos = currentCursorLocation()
        rampStart = Date()
        lastTick = Date()
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        timer.tolerance = 0.002
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func arrowReleased(_ direction: Direction) {
        heldDirections.remove(direction)
        if heldDirections.isEmpty {
            stopAll()
        }
    }

    func stopAll() {
        heldDirections.removeAll()
        timer?.invalidate()
        timer = nil
        rampStart = nil
        lastTick = nil
    }

    func click(_ button: Button) {
        // Live location, not `pos`: clicking must work mid-movement and after
        // the physical mouse has moved.
        let loc = currentCursorLocation()
        let (downType, upType, cgButton): (CGEventType, CGEventType, CGMouseButton) =
            button == .left
                ? (.leftMouseDown, .leftMouseUp, .left)
                : (.rightMouseDown, .rightMouseUp, .right)
        guard
            let down = CGEvent(
                mouseEventSource: nil, mouseType: downType,
                mouseCursorPosition: loc, mouseButton: cgButton),
            let up = CGEvent(
                mouseEventSource: nil, mouseType: upType,
                mouseCursorPosition: loc, mouseButton: cgButton)
        else { return }
        down.setIntegerValueField(.mouseEventClickState, value: 1)
        up.setIntegerValueField(.mouseEventClickState, value: 1)
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    private func tick() {
        guard let rampStart, !heldDirections.isEmpty else { return }
        let now = Date()
        let dt = CGFloat(min(now.timeIntervalSince(lastTick ?? now), 0.05))
        lastTick = now

        // CG global coordinates: origin top-left, +y is down.
        var dx: CGFloat = 0
        var dy: CGFloat = 0
        if heldDirections.contains(.right) { dx += 1 }
        if heldDirections.contains(.left) { dx -= 1 }
        if heldDirections.contains(.down) { dy += 1 }
        if heldDirections.contains(.up) { dy -= 1 }
        guard dx != 0 || dy != 0 else { return }
        if dx != 0, dy != 0 {
            // Normalize so diagonal speed matches cardinal speed.
            let inv = 1 / CGFloat(2).squareRoot()
            dx *= inv
            dy *= inv
        }

        // Ease-in quadratic: precise at the start, fast after rampDuration.
        let t = CGFloat(min(now.timeIntervalSince(rampStart) / rampDuration, 1.0))
        let speed = minSpeed + (maxSpeed - minSpeed) * t * t

        let candidate = CGPoint(x: pos.x + dx * speed * dt, y: pos.y + dy * speed * dt)
        pos = clamp(candidate, from: pos)

        CGEvent(
            mouseEventSource: nil, mouseType: .mouseMoved,
            mouseCursorPosition: pos, mouseButton: .left
        )?.post(tap: .cghidEventTap)
    }

    private func currentCursorLocation() -> CGPoint {
        CGEvent(source: nil)?.location ?? .zero
    }

    private func clamp(_ candidate: CGPoint, from current: CGPoint) -> CGPoint {
        let displays = activeDisplayBounds()
        guard !displays.isEmpty else { return candidate }
        // Inside any display → accept; this is what lets the pointer cross monitors.
        if displays.contains(where: { $0.contains(candidate) }) {
            return candidate
        }
        let bounds = displays.first(where: { $0.contains(current) }) ?? displays[0]
        return CGPoint(
            x: min(max(candidate.x, bounds.minX), bounds.maxX - 1),
            y: min(max(candidate.y, bounds.minY), bounds.maxY - 1))
    }

    private func activeDisplayBounds() -> [CGRect] {
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        guard count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetActiveDisplayList(count, &ids, &count)
        return ids.prefix(Int(count)).map { CGDisplayBounds($0) }
    }
}
