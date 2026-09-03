import SwiftUI

extension ContentUnavailableView where Label == SwiftUI.Label<Text, AppIcon>, Description == Text, Actions == EmptyView {
    init(_ title: LocalizedStringKey, iconName: String, description: Text) {
        self.init {
            SwiftUI.Label { Text(title) } icon: { AppIcon(iconName, size: 48, relativeTo: .largeTitle) }
        } description: {
            description
        }
    }
}
