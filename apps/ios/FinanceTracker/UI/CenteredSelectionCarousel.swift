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

struct CenteredSelectionCarousel<ID: Hashable>: View {
    let items: [CenteredSelectionCarouselItem<ID>]
    @Binding var selection: ID?

    var itemWidth: CGFloat = 74
    var spacing: CGFloat = 4
    var height: CGFloat = 84
    @State private var scrollPosition: ID?

    init(
        items: [CenteredSelectionCarouselItem<ID>],
        selection: Binding<ID?>,
        itemWidth: CGFloat = 74,
        spacing: CGFloat = 4,
        height: CGFloat = 84
    ) {
        self.items = items
        _selection = selection
        self.itemWidth = itemWidth
        self.spacing = spacing
        self.height = height
        _scrollPosition = State(initialValue: nil)
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: spacing) {
                    ForEach(items) { item in
                        itemButton(item)
                            .id(item.id)
                    }
                }
                .padding(.vertical, 8)
                .scrollTargetLayout()
            }
            .contentMargins(
                .horizontal,
                max(0, (proxy.size.width - itemWidth) / 2),
                for: .scrollContent
            )
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.viewAligned(limitBehavior: .always))
            .scrollPosition(id: $scrollPosition, anchor: .center)
        }
        .frame(height: height)
        .task {
            await Task.yield()
            guard !Task.isCancelled else { return }
            scrollPosition = selection
        }
        .onChange(of: scrollPosition) { _, itemID in
            guard let itemID else { return }
            guard selectableItemIDs.contains(itemID) else {
                withAnimation(.snappy(duration: 0.25)) {
                    scrollPosition = selection
                }
                return
            }
            selection = itemID
        }
        .onChange(of: selection) { _, itemID in
            guard scrollPosition != itemID else { return }
            withAnimation(.snappy(duration: 0.25)) {
                scrollPosition = itemID
            }
        }
    }

    private func itemButton(_ item: CenteredSelectionCarouselItem<ID>) -> some View {
        let isSelected = item.action == nil && selection == item.id

        return Button {
            if let action = item.action {
                action()
                return
            }
            if let tapAction = item.tapAction {
                tapAction()
                return
            }
            if isSelected, let selectedAction = item.selectedAction {
                selectedAction()
                return
            }
            withAnimation(.snappy(duration: 0.25)) {
                scrollPosition = item.id
                selection = item.id
            }
        } label: {
            VStack(spacing: 5) {
                AppIcon(item.iconName, size: 21)
                    .foregroundStyle(item.color)
                    .frame(width: 48, height: 48)
                    .background(
                        item.color.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 14)
                    )
                    .overlay(alignment: .bottomTrailing) {
                        if isSelected,
                           let accessoryIcon = item.selectedAccessoryIcon {
                            AppIcon(accessoryIcon, size: 9)
                                .foregroundStyle(Color(uiColor: .systemBackground))
                                .frame(width: 18, height: 18)
                                .background(item.color, in: Circle())
                                .overlay {
                                    Circle()
                                        .stroke(Color(uiColor: .systemBackground), lineWidth: 2)
                                }
                                .offset(x: 5, y: 5)
                                .transition(.scale.combined(with: .opacity))
                                .accessibilityHidden(true)
                        }
                    }
                    .scaleEffect(isSelected ? 1.08 : 1)

                Text(item.title)
                    .font(.caption2.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.primary : .secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .multilineTextAlignment(.center)
            }
            .frame(width: itemWidth)
            .animation(.snappy(duration: 0.25), value: isSelected)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.accessibilityLabel)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var selectableItemIDs: Set<ID> {
        Set(items.lazy.filter { $0.action == nil }.map(\.id))
    }
}
