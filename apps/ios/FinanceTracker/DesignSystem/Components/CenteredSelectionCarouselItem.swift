import SwiftUI

struct CenteredSelectionCarouselItem<ID: Hashable>: Identifiable {
    let id: ID
    let title: String
    let iconName: String
    let color: Color
    let accessibilityLabel: String
    let action: (() -> Void)?
    let tapAction: (() -> Void)?
    let selectedAccessoryIcon: String?
    let selectedAction: (() -> Void)?

    init(
        id: ID,
        title: String,
        iconName: String,
        color: Color,
        accessibilityLabel: String? = nil,
        selectedAccessoryIcon: String? = nil,
        tapAction: (() -> Void)? = nil,
        selectedAction: (() -> Void)? = nil
    ) {
        self.id = id
        self.title = title
        self.iconName = iconName
        self.color = color
        self.accessibilityLabel = accessibilityLabel ?? title
        self.action = nil
        self.tapAction = tapAction
        self.selectedAccessoryIcon = selectedAccessoryIcon
        self.selectedAction = selectedAction
    }

    init(
        id: ID,
        title: String,
        iconName: String,
        color: Color,
        accessibilityLabel: String? = nil,
        action: @escaping () -> Void
    ) {
        self.id = id
        self.title = title
        self.iconName = iconName
        self.color = color
        self.accessibilityLabel = accessibilityLabel ?? title
        self.action = action
        self.tapAction = nil
        self.selectedAccessoryIcon = nil
        self.selectedAction = nil
    }
}
