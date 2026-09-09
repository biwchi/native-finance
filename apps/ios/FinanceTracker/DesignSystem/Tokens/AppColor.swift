import SwiftUI

/// Semantic colors used by shared UI. Feature code should choose a role instead of a raw value.
enum AppColor {
    static let accent = Color("AccentColor")
    static let onAccent = Color("OnAccentColor")
    // Native switches keep a white thumb, even when the app's accent becomes white.
    static let switchTrack = Color("SwitchTrackColor")
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

    /// Keep palette artwork readable on native surfaces and its translucent badge.
    static func iconForeground(for color: Color) -> Color {
        Color(uiColor: UIColor { traits in
            let tint = components(UIColor(color).resolvedColor(with: traits))
            let surfaces = [UIColor.systemBackground, .secondarySystemGroupedBackground,
                            .tertiarySystemGroupedBackground].flatMap { surface in
                let base = components(surface.resolvedColor(with: traits))
                let secondary = components(UIColor.secondaryLabel.resolvedColor(with: traits))
                return [base, zip(tint, base).map { $0 * 0.14 + $1 * 0.86 },
                        zip(secondary, base).map { $0 * 0.12 + $1 * 0.88 }]
            }
            let target = traits.userInterfaceStyle == .dark ? 1.0 : 0.0
            for step in 0...100 {
                let amount = Double(step) / 100
                let ink = tint.map { $0 * (1 - amount) + target * amount }
                let inkLuminance = luminance(ink)
                if surfaces.allSatisfy({ surface in
                    let background = luminance(surface)
                    return (max(inkLuminance, background) + 0.05)
                        / (min(inkLuminance, background) + 0.05) >= 3
                }) {
                    return UIColor(red: ink[0], green: ink[1], blue: ink[2], alpha: 1)
                }
            }
            return target == 1 ? .white : .black
        })
    }

    /// Choose ink from the resolved opaque fill, since palette colors also change with appearance.
    static func foreground(on fill: Color) -> Color {
        Color(uiColor: UIColor { traits in
            let luminance = luminance(components(UIColor(fill).resolvedColor(with: traits)))
            let blackContrast = (luminance + 0.05) / 0.05
            let whiteContrast = 1.05 / (luminance + 0.05)
            return blackContrast >= whiteContrast ? .black : .white
        })
    }

    private static func components(_ color: UIColor) -> [Double] {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: nil)
        return [Double(red), Double(green), Double(blue)]
    }

    private static func luminance(_ components: [Double]) -> Double {
        let linear = components.map { $0 <= 0.04045 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2]
    }
}
