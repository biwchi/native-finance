import Foundation

enum GoalDeadline {
    static func string(from date: Date, timeZone: TimeZone = .current) -> String {
        formatter(timeZone: timeZone).string(from: date)
    }

    static func date(from value: String, timeZone: TimeZone = .current) -> Date? {
        let formatter = formatter(timeZone: timeZone)
        guard value.range(of: "^[0-9]{4}-[0-9]{2}-[0-9]{2}$", options: .regularExpression) != nil,
              let date = formatter.date(from: value), formatter.string(from: date) == value else { return nil }
        return date
    }

    private static func formatter(timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        return formatter
    }
}
