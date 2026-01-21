import SwiftUI

struct TimeRulesView: View {
    @ObservedObject var settings: UserSettings
    
    var body: some View {
        VStack {
            List {
                ForEach(settings.timeRules) { rule in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(rule.name)
                                .font(.headline)
                            Text("\(formatTime(h: rule.startHour, m: rule.startMinute)) - \(formatTime(h: rule.endHour, m: rule.endMinute))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        VStack(alignment: .trailing) {
                            Text("\(rule.targetMin)% - \(rule.targetMax)%")
                                .foregroundColor(.green)
                            Text(daysString(for: rule.daysOfWeek))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        
                        Toggle("", isOn: Binding(
                            get: { rule.enabled },
                            set: { newValue in
                                if let index = settings.timeRules.firstIndex(where: { $0.id == rule.id }) {
                                    settings.timeRules[index].enabled = newValue
                                }
                            }
                        ))
                        .labelsHidden()
                    }
                }
                .onDelete { indexSet in
                    settings.timeRules.remove(atOffsets: indexSet)
                }
            }
            
            Button("Add Rule") {
                // Placeholder for adding a new rule
                // In a real app, this would open a sheet with a TimeRuleEditor
                let newRule = TimeRule(
                    name: "New Rule",
                    daysOfWeek: [1, 2, 3, 4, 5, 6, 7], // All days
                    startHour: 9, startMinute: 0,
                    endHour: 17, endMinute: 0,
                    targetMin: 50, targetMax: 60,
                    enabled: true
                )
                settings.timeRules.append(newRule)
            }
            .padding()
        }
    }
    
    private func formatTime(h: Int, m: Int) -> String {
        return String(format: "%02d:%02d", h, m)
    }
    
    private func daysString(for days: Set<Int>) -> String {
        if days.count == 7 { return "Every Day" }
        if days == [2,3,4,5,6] { return "Weekdays" }
        if days == [1,7] { return "Weekends" }
        return "\(days.count) days"
    }
}
