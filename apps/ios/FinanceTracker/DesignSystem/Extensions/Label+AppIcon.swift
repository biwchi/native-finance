import SwiftUI

extension Label where Title == Text, Icon == Image {
    @MainActor
    init(_ title: LocalizedStringKey, icon: String) {
        self.init { Text(title) } icon: { AppIcons.image(named: icon).renderingMode(.template) }
    }

    @MainActor
    init<S: StringProtocol>(_ title: S, icon: String) {
        self.init { Text(title) } icon: { AppIcons.image(named: icon).renderingMode(.template) }
    }
}
