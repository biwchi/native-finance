import CoreGraphics

enum AppSpacing {
    static let extraSmall: CGFloat = 4
    static let compact: CGFloat = 6
    static let small: CGFloat = 8
    static let medium: CGFloat = 12
    static let large: CGFloat = 16
    static let extraLarge: CGFloat = 20
    static let doubleExtraLarge: CGFloat = 24
    // Older navigation bars leave 6 points above 44-point controls; iOS 26 leaves 16.
    static let legacySheetToolbarTopInset: CGFloat = 10
}
