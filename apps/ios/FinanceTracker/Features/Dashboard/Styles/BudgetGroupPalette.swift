import SwiftUI

enum BudgetGroupPalette {
    private static let colors: [Color] = [
        .blue,
        .purple,
        .orange,
        .teal,
        .pink,
        .indigo,
    ]

    static func color(at index: Int) -> Color {
        colors[index % colors.count]
    }
}
