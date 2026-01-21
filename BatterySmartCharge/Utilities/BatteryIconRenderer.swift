import Cocoa

/// Renders dynamic vertical battery icons based on charging status, mode, and percentage
class BatteryIconRenderer {

    // Icon size optimized for menu bar
    private static let iconSize = NSSize(width: 20, height: 20)

    /// Main entry point: Generate a battery icon based on current state
    static func renderIcon(percentage: Int, isCharging: Bool, action: ChargingAction) -> NSImage {
        let image = NSImage(size: iconSize)

        image.lockFocus()

        // Draw battery outline
        drawBatteryOutline()

        // Draw battery fill based on percentage
        drawBatteryFill(percentage: percentage, action: action)

        // Draw status indicator overlay (charging bolt, trickle icon, etc.)
        drawStatusIndicator(isCharging: isCharging, action: action)

        image.unlockFocus()

        // Make it work in menu bar (support light/dark mode)
        image.isTemplate = true

        return image
    }

    // MARK: - Drawing Components

    private static func drawBatteryOutline() {
        let batteryRect = CGRect(x: 4, y: 2, width: 12, height: 16)
        let terminalRect = CGRect(x: 7, y: 18, width: 6, height: 1.5)

        // Battery body outline
        let path = NSBezierPath(roundedRect: batteryRect, xRadius: 1.5, yRadius: 1.5)
        path.lineWidth = 1.5
        NSColor.controlTextColor.setStroke()
        path.stroke()

        // Battery terminal (top nub)
        let terminalPath = NSBezierPath(roundedRect: terminalRect, xRadius: 0.75, yRadius: 0.75)
        NSColor.controlTextColor.setFill()
        terminalPath.fill()
    }

    private static func drawBatteryFill(percentage: Int, action: ChargingAction) {
        let clamped = max(0, min(100, percentage))

        // Battery interior dimensions (with padding)
        let fillX: CGFloat = 5.5
        let fillWidth: CGFloat = 9
        let fillMaxHeight: CGFloat = 13
        let fillY: CGFloat = 3.5

        // Calculate fill height based on percentage
        let fillHeight = (CGFloat(clamped) / 100.0) * fillMaxHeight
        let fillRect = CGRect(x: fillX, y: fillY, width: fillWidth, height: fillHeight)

        // Use controlTextColor (adapts to light/dark mode) with different patterns/fills
        // Solid fill for most states
        NSColor.controlTextColor.setFill()
        let fillPath = NSBezierPath(roundedRect: fillRect, xRadius: 1, yRadius: 1)
        fillPath.fill()
    }

    private static func drawStatusIndicator(isCharging: Bool, action: ChargingAction) {
        switch action {
        case .chargeActive:
            // Draw charging bolt - larger and more prominent
            drawChargingBolt()

        case .chargeNormal:
            // Draw regular charging bolt
            drawChargingBolt()

        case .chargeTrickle:
            // Draw trickle indicator (wavy line to indicate maintenance)
            drawTrickleIndicator()

        case .rest:
            // Draw small dot indicator for idle state
            drawRestIndicator()

        case .forceStop:
            // Draw X to indicate stopped
            drawStopIndicator()
        }
    }

    private static func drawChargingBolt() {
        // Lightning bolt overlay - positioned in center-right of battery
        let boltPath = NSBezierPath()

        // Larger, more visible bolt
        boltPath.move(to: CGPoint(x: 12, y: 13))
        boltPath.line(to: CGPoint(x: 9.5, y: 9.5))
        boltPath.line(to: CGPoint(x: 11, y: 9.5))
        boltPath.line(to: CGPoint(x: 8.5, y: 6))
        boltPath.line(to: CGPoint(x: 11, y: 9.5))
        boltPath.line(to: CGPoint(x: 9.5, y: 9.5))
        boltPath.close()

        // Use background color to cut out the bolt (creates contrast)
        NSColor.controlBackgroundColor.setFill()
        boltPath.fill()

        // Add a thin outline for definition
        NSColor.controlTextColor.setStroke()
        boltPath.lineWidth = 0.75
        boltPath.stroke()
    }

    private static func drawTrickleIndicator() {
        // Draw wavy/zigzag line to indicate trickle/maintenance mode
        let path = NSBezierPath()
        path.move(to: CGPoint(x: 8, y: 11))
        path.line(to: CGPoint(x: 9, y: 9))
        path.line(to: CGPoint(x: 10, y: 11))
        path.line(to: CGPoint(x: 11, y: 9))
        path.line(to: CGPoint(x: 12, y: 11))

        NSColor.controlTextColor.setStroke()
        path.lineWidth = 1.5
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.stroke()
    }

    private static func drawRestIndicator() {
        // Small circle to indicate idle/resting
        let dotRect = CGRect(x: 9, y: 9, width: 2.5, height: 2.5)
        let dot = NSBezierPath(ovalIn: dotRect)

        NSColor.controlTextColor.setFill()
        dot.fill()
    }

    private static func drawStopIndicator() {
        // Draw X to indicate force stop
        let line1 = NSBezierPath()
        line1.move(to: CGPoint(x: 8.5, y: 8))
        line1.line(to: CGPoint(x: 11.5, y: 12))

        let line2 = NSBezierPath()
        line2.move(to: CGPoint(x: 11.5, y: 8))
        line2.line(to: CGPoint(x: 8.5, y: 12))

        NSColor.controlTextColor.setStroke()
        line1.lineWidth = 2
        line2.lineWidth = 2
        line1.lineCapStyle = .round
        line2.lineCapStyle = .round
        line1.stroke()
        line2.stroke()
    }

}
