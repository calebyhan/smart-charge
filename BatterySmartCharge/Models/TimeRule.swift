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
}
