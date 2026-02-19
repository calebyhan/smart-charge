import Foundation

struct TimeRule: Codable, Identifiable {
    var id = UUID()
    var name: String
    var daysOfWeek: Set<Int> // 1=Sunday, 7=Saturday (matching Calendar.component(.weekday))
    var startHour: Int
    var startMinute: Int
    var endHour: Int
    var endMinute: Int
    var targetMin: Int
    var targetMax: Int
    var enabled: Bool
    
    // Check if the rule is active at a given date
    func isActive(at date: Date, calendar: Calendar = .current) -> Bool {
        guard enabled else { return false }
        
        let components = calendar.dateComponents([.weekday, .hour, .minute], from: date)
        guard let day = components.weekday,
              let hour = components.hour,
              let minute = components.minute else { return false }
        
        if !daysOfWeek.contains(day) { return false }
        
        let currentMinutes = hour * 60 + minute
        let startMinutes = startHour * 60 + startMinute
        let endMinutes = endHour * 60 + endMinute

        if startMinutes <= endMinutes {
            // Inclusive upper bound - rule ending at 09:00 includes 09:00:00-09:00:59
            return currentMinutes >= startMinutes && currentMinutes <= endMinutes
        } else {
            // Spans overnight - inclusive upper bound
            return currentMinutes >= startMinutes || currentMinutes <= endMinutes
        }
    }

    /// Check if this rule overlaps with another rule (same day + overlapping time)
    func overlaps(with other: TimeRule) -> Bool {
        // Both rules must be enabled to have a conflict
        guard enabled && other.enabled else { return false }
        // Must share at least one day
        guard !daysOfWeek.isDisjoint(with: other.daysOfWeek) else { return false }

        let selfStart = startHour * 60 + startMinute
        let selfEnd = endHour * 60 + endMinute
        let otherStart = other.startHour * 60 + other.startMinute
        let otherEnd = other.endHour * 60 + other.endMinute

        let selfIsOvernight = selfStart > selfEnd
        let otherIsOvernight = otherStart > otherEnd

        // Both daytime rules: standard interval overlap check
        if !selfIsOvernight && !otherIsOvernight {
            return selfStart < otherEnd && otherStart < selfEnd
        }

        // Both overnight rules: they always overlap (both cover midnight)
        if selfIsOvernight && otherIsOvernight {
            return true
        }

        // One overnight, one daytime: check if daytime falls within overnight span
        if selfIsOvernight {
            // Self is overnight: covers [selfStart, 24:00) and [00:00, selfEnd]
            // Other is daytime: covers [otherStart, otherEnd]
            return otherStart < selfEnd || otherEnd > selfStart
        } else {
            // Other is overnight
            return selfStart < otherEnd || selfEnd > otherStart
        }
    }
}
