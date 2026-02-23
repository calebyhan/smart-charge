import SwiftUI

private struct TooltipSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}

struct TimelineChartView: View {
    let dataPoints: [Double]
    let historyEntries: [SmartChargeManager.BatteryHistoryEntry]
    let useFahrenheit: Bool

    @State private var hoveredEntry: SmartChargeManager.BatteryHistoryEntry?
    @State private var hoverLocation: CGPoint?
    @State private var tooltipSize: CGSize = CGSize(width: 100, height: 40)

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("24h History")
                .font(.caption)
                .foregroundColor(.secondary)

            if historyEntries.isEmpty {
                Text("No data yet...")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .frame(height: 60)
                    .frame(maxWidth: .infinity)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(4)
            } else {
                VStack(spacing: 2) {
                    GeometryReader { geo in
                        let now = Date()
                        let twentyFourHoursAgo = now.addingTimeInterval(-24 * 60 * 60)
                        let timeSpan: TimeInterval = 24 * 60 * 60 // 24 hours in seconds

                        // Calculate X position based on actual timestamp within 24h window
                        let xPosition: (Date) -> CGFloat = { timestamp in
                            let timeFromStart = timestamp.timeIntervalSince(twentyFourHoursAgo)
                            let normalizedX = timeFromStart / timeSpan
                            return geo.size.width * CGFloat(max(0, min(1, normalizedX)))
                        }

                        // Calculate Y position from percentage (0-100%)
                        let yPosition: (Double) -> CGFloat = { percentage in
                            (1.0 - (percentage / 100.0)) * geo.size.height
                        }

                        // Calculate Y position for temperature (20-50°C or 68-122°F range)
                        let tempYPosition: (Double) -> CGFloat = { tempC in
                            let (minTemp, maxTemp): (Double, Double)
                            let displayTemp: Double

                            if useFahrenheit {
                                // Convert to Fahrenheit for display
                                displayTemp = tempC * 9 / 5 + 32
                                minTemp = 68  // 20°C in F
                                maxTemp = 122 // 50°C in F
                            } else {
                                displayTemp = tempC
                                minTemp = 20
                                maxTemp = 50
                            }

                            let clampedTemp = max(minTemp, min(maxTemp, displayTemp))
                            let normalized = (clampedTemp - minTemp) / (maxTemp - minTemp)
                            return (1.0 - normalized) * geo.size.height
                        }

                        ZStack {
                            // Background
                            Color.secondary.opacity(0.1)

                            // Grid lines for time marks (every 6 hours)
                            ForEach(0..<5) { index in
                                Path { path in
                                    let x = geo.size.width * CGFloat(index) / 4.0
                                    path.move(to: CGPoint(x: x, y: 0))
                                    path.addLine(to: CGPoint(x: x, y: geo.size.height))
                                }
                                .stroke(Color.secondary.opacity(0.2), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                            }

                            // Battery percentage line
                            Path { path in
                                guard !historyEntries.isEmpty else { return }

                                // Start path at first point
                                let firstEntry = historyEntries[0]
                                path.move(to: CGPoint(
                                    x: xPosition(firstEntry.timestamp),
                                    y: yPosition(firstEntry.percentage)
                                ))

                                // Draw lines to subsequent points
                                for entry in historyEntries.dropFirst() {
                                    path.addLine(to: CGPoint(
                                        x: xPosition(entry.timestamp),
                                        y: yPosition(entry.percentage)
                                    ))
                                }
                            }
                            .stroke(Color.blue, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                            // Temperature line (orange, thinner)
                            Path { path in
                                let entriesWithTemp = historyEntries.filter { $0.temperature != nil }
                                guard let firstEntry = entriesWithTemp.first,
                                      let firstTemp = firstEntry.temperature else { return }

                                path.move(to: CGPoint(
                                    x: xPosition(firstEntry.timestamp),
                                    y: tempYPosition(firstTemp)
                                ))

                                for entry in entriesWithTemp.dropFirst() {
                                    if let temp = entry.temperature {
                                        path.addLine(to: CGPoint(
                                            x: xPosition(entry.timestamp),
                                            y: tempYPosition(temp)
                                        ))
                                    }
                                }
                            }
                            .stroke(Color.orange.opacity(0.7), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))

                            // Hover indicator
                            if let entry = hoveredEntry {
                                let x = xPosition(entry.timestamp)
                                let y = yPosition(entry.percentage)

                                // Vertical line
                                Path { path in
                                    path.move(to: CGPoint(x: x, y: 0))
                                    path.addLine(to: CGPoint(x: x, y: geo.size.height))
                                }
                                .stroke(Color.blue.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))

                                // Dot at data point
                                Circle()
                                    .fill(Color.blue)
                                    .frame(width: 6, height: 6)
                                    .position(x: x, y: y)

                                // Tooltip
                                let halfW = tooltipSize.width / 2
                                let halfH = tooltipSize.height / 2
                                let padding: CGFloat = 4
                                let gap: CGFloat = 10

                                // Clamp x so tooltip never leaves chart horizontally
                                let tipX = min(max(x, halfW + padding), geo.size.width - halfW - padding)

                                // Prefer above the dot; flip below if not enough room; clamp both edges
                                let spaceAbove = y - gap - halfH
                                let rawTipY: CGFloat = spaceAbove >= padding
                                    ? spaceAbove + halfH  // above: bottom of tooltip = y - gap
                                    : y + gap + halfH     // below: top of tooltip = y + gap
                                let tipY = min(max(rawTipY, halfH + padding), geo.size.height - halfH - padding)

                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 4) {
                                        Text("\(Int(entry.percentage))%")
                                            .font(.system(size: 10, weight: .semibold))
                                            .foregroundColor(.blue)
                                        if let tempC = entry.temperature {
                                            Text("•")
                                                .font(.system(size: 8))
                                                .foregroundColor(.secondary)
                                            let displayTemp = useFahrenheit ? (tempC * 9 / 5 + 32) : tempC
                                            let unit = useFahrenheit ? "°F" : "°C"
                                            Text(String(format: "%.1f\(unit)", displayTemp))
                                                .font(.system(size: 10, weight: .semibold))
                                                .foregroundColor(.orange)
                                        }
                                    }
                                    Text(formatHoverTime(entry.timestamp))
                                        .font(.system(size: 8))
                                        .foregroundColor(.secondary)
                                }
                                .padding(4)
                                .background(
                                    GeometryReader { tooltipGeo in
                                        Color(nsColor: .controlBackgroundColor)
                                            .preference(key: TooltipSizeKey.self, value: tooltipGeo.size)
                                    }
                                )
                                .cornerRadius(4)
                                .shadow(radius: 2)
                                .position(x: tipX, y: tipY)
                            }
                        }
                        .onPreferenceChange(TooltipSizeKey.self) { size in
                            if size != .zero { tooltipSize = size }
                        }
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let location):
                                hoverLocation = location
                                // Find closest data point
                                findClosestEntry(at: location, in: geo.size, xPosition: xPosition)
                            case .ended:
                                hoveredEntry = nil
                                hoverLocation = nil
                            }
                        }
                    }
                    .frame(height: 60)
                    .cornerRadius(4)

                    // Time labels - positioned to align with grid lines
                    GeometryReader { geo in
                        ForEach(0..<5) { index in
                            Text(timeLabelForIndex(index))
                                .font(.system(size: 8))
                                .foregroundColor(.secondary)
                                .position(
                                    x: geo.size.width * CGFloat(index) / 4.0,
                                    y: 5
                                )
                        }
                    }
                    .frame(height: 10)
                }
            }
        }
    }

    private func timeLabelForIndex(_ index: Int) -> String {
        let hoursAgo = (4 - index) * 6
        if hoursAgo == 0 {
            return "Now"
        } else if hoursAgo == 24 {
            return "24h"
        } else {
            return "\(hoursAgo)h"
        }
    }

    private func findClosestEntry(at location: CGPoint, in size: CGSize, xPosition: (Date) -> CGFloat) {
        guard !historyEntries.isEmpty else { return }

        // Find the entry with the closest x position to the mouse
        var closestEntry = historyEntries[0]
        var minDistance = abs(xPosition(historyEntries[0].timestamp) - location.x)

        for entry in historyEntries {
            let distance = abs(xPosition(entry.timestamp) - location.x)
            if distance < minDistance {
                minDistance = distance
                closestEntry = entry
            }
        }

        hoveredEntry = closestEntry
    }

    private func formatHoverTime(_ date: Date) -> String {
        let now = Date()
        let interval = now.timeIntervalSince(date)

        if interval < 60 {
            return "Just now"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes)m ago"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours)h ago"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d, h:mm a"
            return formatter.string(from: date)
        }
    }
}
