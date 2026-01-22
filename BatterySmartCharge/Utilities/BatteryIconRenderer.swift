import Cocoa

/// Renders dynamic vertical battery icons based on charging status, mode, and percentage
class BatteryIconRenderer {

    // Icon size optimized for menu bar
    private static let iconSize = NSSize(width: 20, height: 20)

    /// Detect if menu bar is in dark mode (light text on dark background)
    private static var isDarkMenuBar: Bool {
        // Check effective appearance
        let appearance = NSApp.effectiveAppearance
        return appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    /// Get the appropriate outline color for current appearance
    private static var outlineColor: NSColor {
        isDarkMenuBar ? .white : .black
    }

    /// Main entry point: Generate a battery icon based on current state
    static func renderIcon(percentage: Int, isCharging: Bool, action: ChargingAction) -> NSImage {
        let image = NSImage(size: iconSize)

        image.lockFocus()

        // Draw battery outline
        drawBatteryOutline()

        // Draw battery fill based on percentage and action
        drawBatteryFill(percentage: percentage, action: action)

        // Draw status indicator overlay (charging bolt, etc.)
        drawStatusIndicator(action: action)

        image.unlockFocus()

        // NOT a template - we want colors to show
        image.isTemplate = false

        return image
    }

    // MARK: - Drawing Components

    private static func drawBatteryOutline() {
        let batteryRect = CGRect(x: 4, y: 2, width: 12, height: 16)
        let terminalRect = CGRect(x: 7, y: 18, width: 6, height: 1.5)

        // Battery body outline
        let path = NSBezierPath(roundedRect: batteryRect, xRadius: 1.5, yRadius: 1.5)
        path.lineWidth = 1.5
        outlineColor.setStroke()
        path.stroke()

        // Battery terminal (top nub)
        let terminalPath = NSBezierPath(roundedRect: terminalRect, xRadius: 0.75, yRadius: 0.75)
        outlineColor.setFill()
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

        // Color based on charging action
        let fillColor = colorForAction(action, percentage: clamped)
        fillColor.setFill()

        let fillPath = NSBezierPath(roundedRect: fillRect, xRadius: 1, yRadius: 1)
        fillPath.fill()
    }

    private static func colorForAction(_ action: ChargingAction, percentage: Int) -> NSColor {
        switch action {
        case .chargeActive, .chargeNormal:
            // Green when actively charging
            return .systemGreen
        case .chargeTrickle:
            // Orange/yellow for trickle/maintenance
            return .systemOrange
        case .rest:
            // Blue for idle/resting
            return .systemBlue
        case .forceStop:
            // Red for stopped
            return .systemRed
        }
    }

    private static func drawStatusIndicator(action: ChargingAction) {
        switch action {
        case .chargeActive, .chargeNormal:
            // Draw charging bolt
            drawChargingBolt()
        case .chargeTrickle:
            // Draw trickle indicator (equals sign)
            drawTrickleIndicator()
        case .rest:
            // Draw pause indicator
            drawRestIndicator()
        case .forceStop:
            // Draw X indicator
            drawStopIndicator()
        }
    }

    private static func drawChargingBolt() {
        let boltPath = NSBezierPath()

        // Lightning bolt centered in battery
        boltPath.move(to: CGPoint(x: 12, y: 14))
        boltPath.line(to: CGPoint(x: 9, y: 10))
        boltPath.line(to: CGPoint(x: 11, y: 10))
        boltPath.line(to: CGPoint(x: 8, y: 5))
        boltPath.line(to: CGPoint(x: 11, y: 9))
        boltPath.line(to: CGPoint(x: 9, y: 9))
        boltPath.close()

        // White bolt for contrast against green fill
        NSColor.white.setFill()
        boltPath.fill()
    }

    private static func drawTrickleIndicator() {
        // Two horizontal lines (equals sign) for maintenance mode
        let line1 = NSBezierPath()
        line1.move(to: CGPoint(x: 7, y: 11))
        line1.line(to: CGPoint(x: 13, y: 11))

        let line2 = NSBezierPath()
        line2.move(to: CGPoint(x: 7, y: 8))
        line2.line(to: CGPoint(x: 13, y: 8))

        NSColor.white.setStroke()
        line1.lineWidth = 2
        line2.lineWidth = 2
        line1.lineCapStyle = .round
        line2.lineCapStyle = .round
        line1.stroke()
        line2.stroke()
    }

    private static func drawRestIndicator() {
        // Two vertical bars (pause symbol)
        let bar1 = NSBezierPath(rect: CGRect(x: 7.5, y: 7, width: 2, height: 6))
        let bar2 = NSBezierPath(rect: CGRect(x: 10.5, y: 7, width: 2, height: 6))

        NSColor.white.setFill()
        bar1.fill()
        bar2.fill()
    }

    private static func drawStopIndicator() {
        // X mark for force stop
        let line1 = NSBezierPath()
        line1.move(to: CGPoint(x: 7.5, y: 7))
        line1.line(to: CGPoint(x: 12.5, y: 13))

        let line2 = NSBezierPath()
        line2.move(to: CGPoint(x: 12.5, y: 7))
        line2.line(to: CGPoint(x: 7.5, y: 13))

        NSColor.white.setStroke()
        line1.lineWidth = 2.5
        line2.lineWidth = 2.5
        line1.lineCapStyle = .round
        line2.lineCapStyle = .round
        line1.stroke()
        line2.stroke()
    }
}
