import Foundation

struct TransactionCommandContext {
    var now: Date
    var calendar: Calendar
    var locale: Locale
    var timeZone: TimeZone
    var currencyCode: String?

    init(
        now: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent,
        locale: Locale = .autoupdatingCurrent,
        timeZone: TimeZone = .autoupdatingCurrent,
        currencyCode: String? = nil
    ) {
        self.now = now
        self.calendar = calendar
        self.locale = locale
        self.timeZone = timeZone
        self.currencyCode = currencyCode
    }
}
