import SwiftUI

extension CategoryColor {
    var swiftUIColor: Color {
        switch self {
        case .red: .red
        case .coral: Color(red: 1.00, green: 0.38, blue: 0.35)
        case .orange: .orange
        case .amber: Color(red: 1.00, green: 0.69, blue: 0.10)
        case .yellow: .yellow
        case .lime: Color(red: 0.66, green: 0.86, blue: 0.16)
        case .green: .green
        case .mint: .mint
        case .teal: .teal
        case .turquoise: Color(red: 0.10, green: 0.78, blue: 0.70)
        case .cyan: .cyan
        case .sky: Color(red: 0.25, green: 0.70, blue: 0.95)
        case .blue: .blue
        case .navy: Color(red: 0.13, green: 0.27, blue: 0.58)
        case .indigo: .indigo
        case .violet: Color(red: 0.49, green: 0.24, blue: 0.93)
        case .purple: .purple
        case .lavender: Color(red: 0.70, green: 0.55, blue: 0.96)
        case .pink: .pink
        case .rose: Color(red: 0.91, green: 0.23, blue: 0.45)
        case .brown: .brown
        case .slate: Color(red: 0.38, green: 0.45, blue: 0.55)
        case .gray: .gray
        }
    }

    var selectionForegroundColor: Color {
        switch self {
        case .amber, .yellow, .lime, .mint, .cyan, .sky, .lavender:
            Color.black.opacity(0.78)
        default:
            .white
        }
    }
}
