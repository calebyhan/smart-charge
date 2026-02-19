import SwiftUI

struct PowerDrawSettingsView: View {
    @ObservedObject var settings: UserSettings

    // Minimum gap between light and heavy thresholds
    private let minGap: Double = 5.0

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Power Thresholds Card
                SettingsCard {
                    VStack(alignment: .leading, spacing: 12) {
                        SettingsCardHeader(
                            icon: "bolt.fill",
                            title: "Usage Thresholds",
                            color: .yellow
                        )

                        Divider()

                        // Visual Power Scale
                        PowerScaleView(
                            lightThreshold: Int(settings.lightUsageThreshold),
                            heavyThreshold: Int(settings.heavyUsageThreshold)
                        )
                        .padding(.vertical, 8)

                        Divider()

                        // Light Usage Slider
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "leaf.fill")
                                    .foregroundColor(.green)
                                    .frame(width: 20)

                                Text("Light Usage")
                                    .font(.subheadline)
                                    .fontWeight(.medium)

                                Spacer()

                                Text("< \(Int(settings.lightUsageThreshold))W")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.green)
                                    .monospacedDigit()
                            }

                            Slider(
                                value: $settings.lightUsageThreshold,
                                in: 5...(settings.heavyUsageThreshold - minGap),
                                step: 1
                            )
                            .tint(.green)
                        }

                        // Heavy Usage Slider
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "flame.fill")
                                    .foregroundColor(.red)
                                    .frame(width: 20)

                                Text("Heavy Usage")
                                    .font(.subheadline)
                                    .fontWeight(.medium)

                                Spacer()

                                Text("> \(Int(settings.heavyUsageThreshold))W")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.red)
                                    .monospacedDigit()
                            }

                            Slider(
                                value: $settings.heavyUsageThreshold,
                                in: (settings.lightUsageThreshold + minGap)...100,
                                step: 1
                            )
                            .tint(.red)
                        }
                    }
                }

                // Info Card
                SettingsCard {
                    VStack(alignment: .leading, spacing: 12) {
                        SettingsCardHeader(
                            icon: "lightbulb.fill",
                            title: "How It Works",
                            color: .orange
                        )

                        Divider()

                        VStack(alignment: .leading, spacing: 12) {
                            PowerInfoRow(
                                icon: "leaf.fill",
                                color: .green,
                                title: "Light Usage",
                                description: "Normal charging behavior, optimized for battery longevity"
                            )

                            PowerInfoRow(
                                icon: "speedometer",
                                color: .yellow,
                                title: "Normal Usage",
                                description: "Balanced charging to maintain power without overcharging"
                            )

                            PowerInfoRow(
                                icon: "flame.fill",
                                color: .red,
                                title: "Heavy Usage",
                                description: "Aggressive charging to prevent drain during demanding tasks"
                            )
                        }
                    }
                }
            }
            .padding()
        }
    }
}

// MARK: - Power Scale Visualization

struct PowerScaleView: View {
    let lightThreshold: Int
    let heavyThreshold: Int

    var body: some View {
        VStack(spacing: 8) {
            // Scale bar
            GeometryReader { geometry in
                let width = geometry.size.width
                let lightPos = CGFloat(lightThreshold) / 100.0 * width
                let heavyPos = CGFloat(heavyThreshold) / 100.0 * width

                ZStack(alignment: .leading) {
                    // Background track
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 24)

                    // Light zone
                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            LinearGradient(
                                colors: [.green.opacity(0.6), .green.opacity(0.4)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: lightPos, height: 24)

                    // Normal zone
                    RoundedRectangle(cornerRadius: 0)
                        .fill(
                            LinearGradient(
                                colors: [.yellow.opacity(0.5), .orange.opacity(0.5)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: heavyPos - lightPos, height: 24)
                        .offset(x: lightPos)

                    // Heavy zone
                    UnevenRoundedRectangle(
                        topLeadingRadius: 0,
                        bottomLeadingRadius: 0,
                        bottomTrailingRadius: 4,
                        topTrailingRadius: 4
                    )
                    .fill(
                        LinearGradient(
                            colors: [.orange.opacity(0.5), .red.opacity(0.6)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: width - heavyPos, height: 24)
                    .offset(x: heavyPos)

                    // Threshold markers
                    Rectangle()
                        .fill(Color.primary.opacity(0.5))
                        .frame(width: 2, height: 24)
                        .offset(x: lightPos - 1)

                    Rectangle()
                        .fill(Color.primary.opacity(0.5))
                        .frame(width: 2, height: 24)
                        .offset(x: heavyPos - 1)
                }
            }
            .frame(height: 24)

            // Labels
            HStack {
                Text("0W")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                Spacer()

                Text("\(lightThreshold)W")
                    .font(.caption2)
                    .foregroundColor(.green)

                Spacer()

                Text("\(heavyThreshold)W")
                    .font(.caption2)
                    .foregroundColor(.red)

                Spacer()

                Text("100W")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Info Row Component

struct PowerInfoRow: View {
    let icon: String
    let color: Color
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}
