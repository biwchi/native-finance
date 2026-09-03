import SwiftUI

struct CategoryIconOption: Identifiable, Hashable {
    let symbol: String
    let title: String

    var id: String { symbol }
}
