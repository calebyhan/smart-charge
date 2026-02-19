import SwiftUI

struct TimeRulesView: View {
    @ObservedObject var settings: UserSettings

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Header Card
                SettingsCard {
                    VStack(alignment: .leading, spacing: 12) {
                        SettingsCardHeader(
                            icon: "clock.fill",
                            title: "Time-Based Rules",
                            color: .purple
                        )

                        Divider()

                        Text("Create rules to automatically adjust charging thresholds based on time of day and day of week.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                // Overlap Warning Banner
                if !settings.getOverlappingRules().isEmpty {
                    SettingsCard {
                        HStack(spacing: 10) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.yellow)
                                .font(.title3)

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Overlapping Rules")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)

                                Text("Some rules overlap. The first matching rule will be used.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.yellow.opacity(0.5), lineWidth: 1)
                    )
                }

                // Rules List
                if settings.timeRules.isEmpty {
                    // Empty State
                    SettingsCard {
                        VStack(spacing: 16) {
                            Image(systemName: "calendar.badge.plus")
                                .font(.system(size: 40))
                                .foregroundColor(.secondary)

                            Text("No Rules Yet")
                                .font(.headline)
                                .foregroundColor(.secondary)

                            Text("Add a rule to customize charging behavior for different times.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                    }
                } else {
                    ForEach(settings.timeRules) { rule in
                        TimeRuleCard(
                            rule: rule,
                            onToggle: { newValue in
                                if let index = settings.timeRules.firstIndex(where: { $0.id == rule.id }) {
                                    settings.timeRules[index].enabled = newValue
                                }
                            },
                            onDelete: {
                                if let index = settings.timeRules.firstIndex(where: { $0.id == rule.id }) {
                                    withAnimation {
                                        settings.timeRules.remove(at: index)
                                    }
                                }
                            }
                        )
                    }
                }

                // Add Rule Button
                Button(action: {
                    let newRule = TimeRule(
                        name: "New Rule",
                        daysOfWeek: [1, 2, 3, 4, 5, 6, 7],
                        startHour: 9, startMinute: 0,
                        endHour: 17, endMinute: 0,
                        targetMin: 50, targetMax: 60,
                        enabled: true
                    )
                    withAnimation {
                        settings.timeRules.append(newRule)
                    }
                }) {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text("Add Rule")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            .padding()
        }
    }
}

// MARK: - Time Rule Card

struct TimeRuleCard: View {
    let rule: TimeRule
    let onToggle: (Bool) -> Void
    let onDelete: () -> Void

    var body: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 12) {
                // Header with name and toggle
                HStack {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(rule.enabled ? Color.green : Color.gray)
                            .frame(width: 8, height: 8)

                        Text(rule.name)
                            .font(.headline)
                    }

                    Spacer()

                    Toggle("", isOn: Binding(
                        get: { rule.enabled },
                        set: onToggle
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .tint(.green)
                }

                Divider()

                // Time and Days Row
                HStack(spacing: 16) {
                    // Time
                    HStack(spacing: 6) {
                        Image(systemName: "clock")
                            .foregroundColor(.blue)
                            .font(.caption)

                        Text("\(formatTime(h: rule.startHour, m: rule.startMinute)) – \(formatTime(h: rule.endHour, m: rule.endMinute))")
                            .font(.subheadline)
                            .monospacedDigit()
                    }

                    Spacer()

                    // Days
                    HStack(spacing: 6) {
                        Image(systemName: "calendar")
                            .foregroundColor(.purple)
                            .font(.caption)

                        Text(daysString(for: rule.daysOfWeek))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }

                // Target Range
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: "battery.50percent")
                            .foregroundColor(.green)
                            .font(.caption)

                        Text("Target: \(rule.targetMin)% – \(rule.targetMax)%")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.green)
                    }

                    Spacer()

                    // Delete button
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                }

                // Visual range indicator
                TimeRuleRangeIndicator(min: rule.targetMin, max: rule.targetMax)
            }
        }
        .opacity(rule.enabled ? 1.0 : 0.6)
    }

    private func formatTime(h: Int, m: Int) -> String {
        return String(format: "%02d:%02d", h, m)
    }

    private func daysString(for days: Set<Int>) -> String {
        if days.count == 7 { return "Every Day" }
        if days == [2, 3, 4, 5, 6] { return "Weekdays" }
        if days == [1, 7] { return "Weekends" }
        return "\(days.count) days"
    }
}

// MARK: - Range Indicator

struct TimeRuleRangeIndicator: View {
    let min: Int
    let max: Int

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let minPos = CGFloat(min) / 100.0 * width
            let maxPos = CGFloat(max) / 100.0 * width

            ZStack(alignment: .leading) {
                // Background
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.gray.opacity(0.2))
                    .frame(height: 6)

                // Active range
                RoundedRectangle(cornerRadius: 3)
                    .fill(
                        LinearGradient(
                            colors: [.green.opacity(0.6), .green],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: maxPos - minPos, height: 6)
                    .offset(x: minPos)
            }
        }
        .frame(height: 6)
    }
}
