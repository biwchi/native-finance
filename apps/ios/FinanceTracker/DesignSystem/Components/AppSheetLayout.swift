/// Navigation sheets receive the shared toolbar inset on older iOS versions.
/// Content sheets, such as a camera or measured date filter, own their internal spacing.
enum AppSheetLayout {
    case navigation
    case content
}
