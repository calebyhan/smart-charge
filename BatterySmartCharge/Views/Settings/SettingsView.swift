import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: UserSettings

    var body: some View {
        TabView {
            GeneralSettingsView(settings: settings)
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            TimeRulesView(settings: settings)
                .tabItem {
                    Label("Time Rules", systemImage: "clock")
                }

            PowerDrawSettingsView(settings: settings)
                .tabItem {
                    Label("Power", systemImage: "bolt")
                }

            BatteryHealthView(manager: SmartChargeManager.shared)
                .tabItem {
                    Label("Health", systemImage: "heart.text.square")
                }

            AboutView()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .padding()
        .frame(width: 500, height: 400)
    }
}

struct RangeSlider: View {
    @Binding var minValue: Int
    @Binding var maxValue: Int
    let range: ClosedRange<Int>

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let minPos = positionFor(value: minValue, in: width)
            let maxPos = positionFor(value: maxValue, in: width)

            ZStack(alignment: .leading) {
                // Track background
                Capsule()
                    .fill(Color.gray.opacity(0.3))
                    .frame(height: 6)

                // Selected range
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: maxPos - minPos, height: 6)
                    .offset(x: minPos)

                // Min handle
                Circle()
                    .fill(Color.white)
                    .frame(width: 20, height: 20)
                    .shadow(radius: 2)
                    .offset(x: minPos - 10)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                let newValue = valueFor(position: value.location.x, in: width)
                                minValue = min(newValue, maxValue - 5)
                            }
                    )

                // Max handle
                Circle()
                    .fill(Color.white)
                    .frame(width: 20, height: 20)
                    .shadow(radius: 2)
                    .offset(x: maxPos - 10)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                let newValue = valueFor(position: value.location.x, in: width)
                                maxValue = max(newValue, minValue + 5)
                            }
                    )
            }
        }
        .frame(height: 20)
    }

    private func positionFor(value: Int, in width: CGFloat) -> CGFloat {
        let percent = CGFloat(value - range.lowerBound) / CGFloat(range.upperBound - range.lowerBound)
        return percent * width
    }

    private func valueFor(position: CGFloat, in width: CGFloat) -> Int {
        let percent = max(0, min(1, position / width))
        return range.lowerBound + Int(percent * CGFloat(range.upperBound - range.lowerBound))
    }
}

struct GeneralSettingsView: View {
    @ObservedObject var settings: UserSettings

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Charging Thresholds Card
                SettingsCard {
                    VStack(alignment: .leading, spacing: 12) {
                        SettingsCardHeader(
                            icon: "battery.75percent",
                            title: "Charging Thresholds",
                            color: .green
                        )

                        Divider()

                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Start Charging")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text("\(settings.minThreshold)%")
                                        .font(.title3)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.orange)
                                }

                                Spacer()

                                Image(systemName: "arrow.right")
                                    .foregroundColor(.secondary)

                                Spacer()

                                VStack(alignment: .trailing, spacing: 2) {
                                    Text("Stop Charging")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text("\(settings.maxThreshold)%")
                                        .font(.title3)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.green)
                                }
                            }
                            .padding(.vertical, 4)

                            RangeSlider(
                                minValue: $settings.minThreshold,
                                maxValue: $settings.maxThreshold,
                                range: 5...100
                            )
                            .padding(.horizontal, 4)
                        }

                        Text("Battery will charge between these levels to optimize longevity.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                // Preferences Card
                SettingsCard {
                    VStack(alignment: .leading, spacing: 12) {
                        SettingsCardHeader(
                            icon: "gearshape",
                            title: "Preferences",
                            color: .blue
                        )

                        Divider()

                        // Launch at Login
                        HStack {
                            Image(systemName: "arrow.right.circle")
                                .foregroundColor(.blue)
                                .frame(width: 24)

                            Text("Launch at Login")
                                .font(.subheadline)

                            Spacer()

                            Toggle("", isOn: Binding(
                                get: { settings.launchAtLogin },
                                set: { newValue in
                                    settings.launchAtLogin = newValue
                                    LaunchHelper.setLaunchAtLogin(newValue)
                                }
                            ))
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .tint(.blue)
                        }

                        Divider()

                        // Temperature Unit
                        HStack {
                            Image(systemName: "thermometer")
                                .foregroundColor(.orange)
                                .frame(width: 24)

                            Text("Temperature Unit")
                                .font(.subheadline)

                            Spacer()

                            Picker("", selection: $settings.useFahrenheit) {
                                Text("°C").tag(false)
                                Text("°F").tag(true)
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 100)
                        }
                    }
                }
            }
            .padding()
        }
    }
}

// MARK: - Reusable Settings Components

struct SettingsCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
            )
    }
}

struct SettingsCardHeader: View {
    let icon: String
    let title: String
    let color: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)
                .frame(width: 28, height: 28)
                .background(color.opacity(0.15))
                .cornerRadius(6)

            Text(title)
                .font(.headline)
        }
    }
}

struct AboutView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // App Info Card
                SettingsCard {
                    VStack(spacing: 16) {
                        // App Icon and Name
                        VStack(spacing: 8) {
                            ZStack {
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [.green.opacity(0.8), .green],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 80, height: 80)

                                Image(systemName: "bolt.batteryblock.fill")
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 44, height: 44)
                                    .foregroundColor(.white)
                            }

                            Text("Smart Charge")
                                .font(.title2)
                                .fontWeight(.bold)

                            Text("Version 1.1.1")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 4)
                                .background(Color.gray.opacity(0.15))
                                .cornerRadius(10)
                        }

                        Divider()

                        Text("Intelligent battery management for macOS.\nOptimize your battery health with smart charging control.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .lineSpacing(4)
                    }
                }

                // Links Card
                SettingsCard {
                    VStack(alignment: .leading, spacing: 12) {
                        SettingsCardHeader(
                            icon: "link",
                            title: "Links",
                            color: .purple
                        )

                        Divider()

                        Link(destination: URL(string: "https://github.com/calebyhan/smart-charge")!) {
                            HStack {
                                Image(systemName: "chevron.left.forwardslash.chevron.right")
                                    .foregroundColor(.purple)
                                    .frame(width: 24)

                                Text("View on GitHub")
                                    .font(.subheadline)
                                    .foregroundColor(.primary)

                                Spacer()

                                Image(systemName: "arrow.up.right")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                        .focusable(false)
                        .buttonStyle(.plain)

                        Divider()

                        Link(destination: URL(string: "https://github.com/calebyhan/smart-charge/issues")!) {
                            HStack {
                                Image(systemName: "exclamationmark.bubble")
                                    .foregroundColor(.orange)
                                    .frame(width: 24)

                                Text("Report an Issue")
                                    .font(.subheadline)
                                    .foregroundColor(.primary)

                                Spacer()

                                Image(systemName: "arrow.up.right")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                        .focusable(false)
                        .buttonStyle(.plain)
                    }
                }

                // Quit Button
                Button(action: {
                    NSApplication.shared.terminate(nil)
                }) {
                    HStack {
                        Image(systemName: "power")
                        Text("Quit Smart Charge")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.large)
            }
            .padding()
        }
    }
}

// MARK: - Battery Health View

struct BatteryHealthView: View {
    @ObservedObject var manager: SmartChargeManager

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Current Status Card
                SettingsCard {
                    VStack(alignment: .leading, spacing: 12) {
                        SettingsCardHeader(
                            icon: "heart.text.square",
                            title: "Battery Status",
                            color: .red
                        )

                        Divider()

                        HStack(spacing: 24) {
                            // Health
                            VStack(alignment: .center, spacing: 4) {
                                Text("\(manager.monitor.state.health)%")
                                    .font(.title)
                                    .fontWeight(.bold)
                                    .foregroundColor(healthColor(manager.monitor.state.health))
                                Text("Health")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity)

                            Divider()
                                .frame(height: 40)

                            // Cycle Count
                            VStack(alignment: .center, spacing: 4) {
                                Text("\(manager.monitor.state.cycleCount)")
                                    .font(.title)
                                    .fontWeight(.bold)
                                    .foregroundColor(.blue)
                                Text("Cycles")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity)

                            Divider()
                                .frame(height: 40)

                            // Cycles Saved
                            VStack(alignment: .center, spacing: 4) {
                                Text("~\(Int(manager.estimatedCyclesSaved))")
                                    .font(.title)
                                    .fontWeight(.bold)
                                    .foregroundColor(.purple)
                                Text("Saved")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .padding(.vertical, 8)

                        Text("Battery health degrades over time with use. Cycles saved is estimated vs. daily 100% charging.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                // Health History Chart
                SettingsCard {
                    VStack(alignment: .leading, spacing: 12) {
                        SettingsCardHeader(
                            icon: "chart.line.uptrend.xyaxis",
                            title: "Health Trend",
                            color: .green
                        )

                        Divider()

                        if manager.healthHistory.isEmpty {
                            VStack(spacing: 8) {
                                Image(systemName: "chart.line.uptrend.xyaxis")
                                    .font(.largeTitle)
                                    .foregroundColor(.secondary)
                                Text("No history yet")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                Text("Health is recorded weekly. Check back in a few weeks to see your trend.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 20)
                        } else if manager.healthHistory.count == 1 {
                            // Show baseline with helpful message
                            VStack(spacing: 8) {
                                HealthTrendChart(entries: manager.healthHistory)
                                    .frame(height: 80)

                                HStack {
                                    Image(systemName: "info.circle")
                                        .foregroundColor(.blue)
                                        .font(.caption)
                                    Text("Baseline recorded. Trend will appear after next weekly check.")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                }
                            }
                        } else {
                            HealthTrendChart(entries: manager.healthHistory)
                                .frame(height: 80)

                            if let first = manager.healthHistory.first,
                               let last = manager.healthHistory.last,
                               manager.healthHistory.count > 1 {
                                let degradation = first.health - last.health
                                let weeks = manager.healthHistory.count
                                HStack {
                                    Text("Change: \(degradation > 0 ? "-" : "+")\(abs(degradation))% over \(weeks) weeks")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                }
                            }
                        }
                    }
                }

                // Session Log Card
                SettingsCard {
                    VStack(alignment: .leading, spacing: 12) {
                        SettingsCardHeader(
                            icon: "list.bullet.rectangle",
                            title: "Charging Log",
                            color: .blue
                        )

                        Divider()

                        if manager.sessionLog.isEmpty {
                            VStack(spacing: 8) {
                                Image(systemName: "doc.text")
                                    .font(.title2)
                                    .foregroundColor(.secondary)
                                Text("No sessions logged yet")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                        } else {
                            ScrollView {
                                VStack(spacing: 8) {
                                    ForEach(manager.sessionLog.suffix(10).reversed()) { entry in
                                        SessionLogRow(entry: entry)
                                    }
                                }
                            }
                            .frame(maxHeight: 150)
                        }
                    }
                }
            }
            .padding()
        }
    }

    private func healthColor(_ health: Int) -> Color {
        if health >= 90 { return .green }
        if health >= 80 { return .yellow }
        return .red
    }
}

struct HealthTrendChart: View {
    let entries: [SmartChargeManager.HealthHistoryEntry]

    var body: some View {
        GeometryReader { geo in
            let minHealth = (entries.map { $0.health }.min() ?? 80) - 5
            let maxHealth = 100

            // Y position for health value
            let yPosition: (Int) -> CGFloat = { health in
                let normalized = CGFloat(health - minHealth) / CGFloat(maxHealth - minHealth)
                return (1.0 - normalized) * geo.size.height
            }

            // X position for entry index
            let xPosition: (Int) -> CGFloat = { index in
                guard entries.count > 1 else { return geo.size.width / 2 }
                return CGFloat(index) / CGFloat(entries.count - 1) * geo.size.width
            }

            ZStack {
                // Background
                Color.secondary.opacity(0.1)
                    .cornerRadius(4)

                // Health line
                Path { path in
                    guard !entries.isEmpty else { return }
                    path.move(to: CGPoint(x: xPosition(0), y: yPosition(entries[0].health)))
                    for (index, entry) in entries.enumerated().dropFirst() {
                        path.addLine(to: CGPoint(x: xPosition(index), y: yPosition(entry.health)))
                    }
                }
                .stroke(Color.green, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                // Data points
                ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)
                        .position(x: xPosition(index), y: yPosition(entry.health))
                }
            }
        }
    }
}

struct SessionLogRow: View {
    let entry: SmartChargeManager.ChargingSessionEntry

    var body: some View {
        HStack(spacing: 8) {
            // Action indicator
            Circle()
                .fill(actionColor(entry.newAction))
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(entry.newAction.description)
                        .font(.caption)
                        .fontWeight(.medium)
                    Text("•")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text("\(entry.batteryPercent)%")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Text(entry.reason)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text(formatTime(entry.timestamp))
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(6)
    }

    private func actionColor(_ action: ChargingAction) -> Color {
        switch action {
        case .chargeActive: return .green
        case .rest: return .blue
        case .forceStop: return .red
        }
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }
}
