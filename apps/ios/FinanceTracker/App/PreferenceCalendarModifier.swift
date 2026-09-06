import SwiftUI

struct PreferenceCalendarModifier: ViewModifier {
    @Environment(\.calendar) private var calendar
    @AppStorage(AppPreferences.firstWeekdayKey) private var firstWeekday = 0

    func body(content: Content) -> some View {
        content.environment(\.calendar, AppPreferences.calendar(firstWeekday: firstWeekday, base: calendar))
    }
}
