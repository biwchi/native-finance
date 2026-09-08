import SwiftUI

/// Semantic colors used by shared UI. Feature code should choose a role instead of a raw value.
enum AppColor {
    static let accent = Color("AccentColor")
    static let onAccent = Color("OnAccentColor")
    static let summarySurface = Color("SummarySurfaceColor")
    static let tealIcon = Color("TealIconColor")
    static let tealIconBackground = Color("TealIconBackgroundColor")
    static let orangeIcon = Color("OrangeIconColor")
    static let orangeIconBackground = Color("OrangeIconBackgroundColor")
    static let blueIcon = Color("BlueIconColor")
    static let blueIconBackground = Color("BlueIconBackgroundColor")

    static let background = Color(uiColor: .systemBackground)
    static let groupedBackground = Color(uiColor: .systemGroupedBackground)
    static let elevatedSurface = Color(uiColor: .secondarySystemGroupedBackground)
    static let controlFill = Color(uiColor: .tertiarySystemFill)
    static let keypadUtilityFill = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? .secondarySystemBackground : .systemGray4
    })
    static let separator = Color(uiColor: .separator)

    static let positive = Color(uiColor: .systemGreen)
    // Text on glass needs stronger contrast than the system's light-mode status fills.
    static let positiveText = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? .systemGreen : UIColor(red: 0.03, green: 0.43, blue: 0.25, alpha: 1)
    })
    static let destructiveText = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? .systemRed : UIColor(red: 0.70, green: 0.12, blue: 0.09, alpha: 1)
    })
    static let destructive = Color(uiColor: .systemRed)
    static let warning = Color(uiColor: .systemOrange)
    static let warningText = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? .systemOrange : UIColor(red: 0.68, green: 0.31, blue: 0.02, alpha: 1)
    })
    static let informative = Color(uiColor: .systemBlue)
}
