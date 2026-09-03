import Foundation

enum CategoryColor: String, Codable, CaseIterable, Identifiable {
    case red
    case coral
    case orange
    case amber
    case yellow
    case lime
    case green
    case mint
    case teal
    case turquoise
    case cyan
    case sky
    case blue
    case navy
    case indigo
    case violet
    case purple
    case lavender
    case pink
    case rose
    case brown
    case slate
    case gray

    var id: Self { self }

    var title: String { rawValue.capitalized }
}
