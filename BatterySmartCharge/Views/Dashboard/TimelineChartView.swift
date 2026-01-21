import SwiftUI

struct TimelineChartView: View {
    let dataPoints: [Double]
    let historyEntries: [SmartChargeManager.BatteryHistoryEntry]

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
                ZStack(alignment: .bottom) {
                    GeometryReader { geo in
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
                                let now = Date()
                                let twentyFourHoursAgo = now.addingTimeInterval(-24 * 60 * 60)
                                let timeSpan: TimeInterval = 24 * 60 * 60 // 24 hours in seconds

                                guard !historyEntries.isEmpty else { return }

                                // Calculate X position based on actual timestamp within 24h window
                                func xPosition(for timestamp: Date) -> CGFloat {
                                    let timeFromStart = timestamp.timeIntervalSince(twentyFourHoursAgo)
                                    let normalizedX = timeFromStart / timeSpan
                                    return geo.size.width * CGFloat(max(0, min(1, normalizedX)))
                                }

                                // Calculate Y position from percentage
                                func yPosition(for percentage: Double) -> CGFloat {
                                    return (1.0 - (percentage / 100.0)) * geo.size.height
                                }

                                // Start path at first point
                                let firstEntry = historyEntries[0]
                                path.move(to: CGPoint(
                                    x: xPosition(for: firstEntry.timestamp),
                                    y: yPosition(for: firstEntry.percentage)
                                ))

                                // Draw lines to subsequent points
                                for entry in historyEntries.dropFirst() {
                                    path.addLine(to: CGPoint(
                                        x: xPosition(for: entry.timestamp),
                                        y: yPosition(for: entry.percentage)
                                    ))
                                }
                            }
                            .stroke(Color.blue, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                        }
                    }
                    .frame(height: 60)
                    .cornerRadius(4)

                    // Time labels
                    HStack(spacing: 0) {
                        ForEach(0..<5) { index in
                            Text(timeLabelForIndex(index))
                                .font(.system(size: 8))
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: index == 0 ? .leading : (index == 4 ? .trailing : .center))
                        }
                    }
                    .padding(.horizontal, 2)
                    .offset(y: 10)
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
}
