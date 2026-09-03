import SwiftUI

/// Semantic colors used by shared UI. Feature code should choose a role instead of a raw value.
enum AppColor {
    static let accent = Color("AccentColor")
    static let onAccent = Color("OnAccentColor")
    static let summarySurface = Color("SummarySurfaceColor")

    static let background = Color(uiColor: .systemBackground)
    static let groupedBackground = Color(uiColor: .systemGroupedBackground)
    static let elevatedSurface = Color(uiColor: .secondarySystemGroupedBackground)
    static let controlFill = Color(uiColor: .tertiarySystemFill)
    static let separator = Color(uiColor: .separator)

    static let positive = Color(uiColor: .systemGreen)
    static let destructive = Color(uiColor: .systemRed)
    static let warning = Color(uiColor: .systemOrange)
    static let informative = Color(uiColor: .systemBlue)
}
