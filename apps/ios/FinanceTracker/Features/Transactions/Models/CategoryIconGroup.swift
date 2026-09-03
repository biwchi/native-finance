import SwiftUI

struct CategoryIconGroup: Identifiable, Hashable {
    let title: String
    let symbol: String
    let icons: [CategoryIconOption]

    var id: String { title }
}
