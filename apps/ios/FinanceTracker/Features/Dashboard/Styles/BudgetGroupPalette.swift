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

    static func color(for id: UUID) -> Color {
        // Unlike hashValue or list position, this stays stable across launches and pool reordering.
        // Keep normal progress distinct from amber budget warnings.
        let poolColors = [0, 1, 3, 5]
        let index = id.uuidString.utf8.reduce(0) { ($0 * 31 + Int($1)) % poolColors.count }
        return color(at: poolColors[index])
    }
}
