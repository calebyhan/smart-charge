import SwiftUI

struct SankeyEnergyFlowView: View {
    let cpuPower: Double
    let gpuPower: Double
    let totalPower: Double
    let isCharging: Bool
    let batteryPower: Double // Positive when charging battery, negative when discharging

    // Calculate "other" power (display, memory, storage, etc.)
    var otherPower: Double {
        max(0, totalPower - cpuPower - gpuPower)
    }

    // Calculate total consumption (what's actually being used by components)
    var totalConsumption: Double {
        cpuPower + gpuPower + otherPower
    }

    // Calculate excess power (what's available for battery charging when plugged in)
    var excessPower: Double {
        guard isCharging else { return 0 }
        // batteryPower is positive when charging
        return max(0, batteryPower)
    }

    // Calculate total AC input power (when plugged in)
    var acInputPower: Double {
        guard isCharging else { return totalPower }
        // AC input = system consumption + battery charging
        return totalConsumption + excessPower
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Power Flow")
                .font(.caption)
                .foregroundColor(.secondary)

            GeometryReader { geometry in
                let width = geometry.size.width
                let height = geometry.size.height

                // Icon position on left
                let iconX: CGFloat = 20
                let iconY = height / 2

                // Flow lines start to the right of the icon
                let flowStartX: CGFloat = 50
                let flowStartY = height / 2

                // Destinations on right
                let destX: CGFloat = width - 60

                // Calculate vertical positions for even distribution
                let flowCount = (cpuPower > 0.01 ? 1 : 0) +
                              (gpuPower > 0.01 ? 1 : 0) +
                              (otherPower > 0.01 ? 1 : 0) +
                              (excessPower > 0.01 ? 1 : 0)

                let cpuFlowIndex = 0
                let gpuFlowIndex = cpuFlowIndex + (cpuPower > 0.01 ? 1 : 0)
                let otherFlowIndex = gpuFlowIndex + (gpuPower > 0.01 ? 1 : 0)
                let batteryFlowIndex = otherFlowIndex + (otherPower > 0.01 ? 1 : 0)

                ZStack {
                    // Background
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(NSColor.controlBackgroundColor))

                    // Flow lines - evenly distributed
                    if cpuPower > 0.01 {
                        FlowLine(
                            start: CGPoint(x: flowStartX, y: flowStartY),
                            end: CGPoint(x: destX, y: height * (CGFloat(cpuFlowIndex) + 0.5) / CGFloat(max(1, flowCount))),
                            width: flowWidth(cpuPower),
                            color: isCharging ? .green : .orange,
                            label: "CPU",
                            value: cpuPower
                        )
                    }

                    if gpuPower > 0.01 {
                        FlowLine(
                            start: CGPoint(x: flowStartX, y: flowStartY),
                            end: CGPoint(x: destX, y: height * (CGFloat(gpuFlowIndex) + 0.5) / CGFloat(max(1, flowCount))),
                            width: flowWidth(gpuPower),
                            color: isCharging ? .green : .orange,
                            label: "GPU",
                            value: gpuPower
                        )
                    }

                    if otherPower > 0.01 {
                        FlowLine(
                            start: CGPoint(x: flowStartX, y: flowStartY),
                            end: CGPoint(x: destX, y: height * (CGFloat(otherFlowIndex) + 0.5) / CGFloat(max(1, flowCount))),
                            width: flowWidth(otherPower),
                            color: isCharging ? .green : .orange,
                            label: "Other",
                            value: otherPower
                        )
                    }

                    // Excess power to battery (if charging)
                    if excessPower > 0.01 {
                        FlowLine(
                            start: CGPoint(x: flowStartX, y: flowStartY),
                            end: CGPoint(x: destX, y: height * (CGFloat(batteryFlowIndex) + 0.5) / CGFloat(max(1, flowCount))),
                            width: flowWidth(excessPower),
                            color: .green,
                            label: "Battery",
                            value: excessPower
                        )
                    }

                    // Source icon - positioned to the left of flow lines
                    VStack(spacing: 2) {
                        Image(systemName: isCharging ? "powerplug.fill" : "battery.100percent")
                            .font(.title3)
                            .foregroundColor(isCharging ? .green : .orange)
                        Text(isCharging ? "AC" : "Batt")
                            .font(.system(size: 8))
                            .foregroundColor(.secondary)
                    }
                    .position(x: iconX, y: iconY)
                }
            }
            .frame(height: 120)

            // Total power display
            if isCharging {
                HStack(spacing: 4) {
                    Text(String(format: "%.1f W", acInputPower))
                        .font(.headline)
                    Text("AC Input")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("•")
                        .foregroundColor(.secondary)
                    Text(String(format: "%.1f W", excessPower))
                        .font(.subheadline)
                    Text("to Battery")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
            } else {
                Text(String(format: "%.1f W Total", totalPower))
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }

    // Calculate flow line width based on power (logarithmic scale for better visibility)
    private func flowWidth(_ power: Double) -> CGFloat {
        // Use logarithmic scale: width = 2 + 8 * log10(power + 1)
        // This gives: 0.1W→2px, 1W→4px, 10W→10px, 100W→18px
        let width = 2 + 8 * log10(power + 1)
        return CGFloat(min(20, max(2, width)))
    }
}

struct FlowLine: View {
    let start: CGPoint
    let end: CGPoint
    let width: CGFloat
    let color: Color
    let label: String
    let value: Double

    var body: some View {
        ZStack {
            // Flow path (curved)
            Path { path in
                let controlPoint1 = CGPoint(x: start.x + (end.x - start.x) * 0.4, y: start.y)
                let controlPoint2 = CGPoint(x: start.x + (end.x - start.x) * 0.6, y: end.y)

                path.move(to: start)
                path.addCurve(to: end, control1: controlPoint1, control2: controlPoint2)
            }
            .stroke(color.opacity(0.6), style: StrokeStyle(lineWidth: width, lineCap: .round))

            // Label at destination
            VStack(spacing: 2) {
                Text(label)
                    .font(.system(size: 9, weight: .medium))
                Text(String(format: "%.1fW", value))
                    .font(.system(size: 8))
                    .foregroundColor(.secondary)
            }
            .position(x: end.x + 30, y: end.y)
        }
    }
}
