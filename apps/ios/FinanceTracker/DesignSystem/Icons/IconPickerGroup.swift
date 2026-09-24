import SwiftUI

struct IconPickerGroup: Identifiable, Hashable {
    let title: String
    let symbol: String
    let icons: [IconPickerOption]

    var id: String { title }
}
