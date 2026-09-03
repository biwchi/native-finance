import Foundation

enum AccountIconColor: String, Codable, CaseIterable, Identifiable {
    case blue
    case indigo
    case purple
    case pink
    case red
    case orange
    case green
    case teal
    case gray

    var id: Self { self }

    var title: String {
        rawValue.capitalized
    }
}
