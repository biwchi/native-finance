import SwiftUI

struct CenteredSelectionCarousel<ID: Hashable>: View {
    let items: [CenteredSelectionCarouselItem<ID>]
    @Binding var selection: ID?

    @State private var scrollPosition: ID?

    init(
        items: [CenteredSelectionCarouselItem<ID>],
        selection: Binding<ID?>
    ) {
        self.items = items
        _selection = selection
        _scrollPosition = State(initialValue: nil)
    }

    var body: some View {
        GeometryReader { proxy in
            carousel(in: proxy)
        }
        .frame(height: Self.preferredHeight)
        .task {
            await Task.yield()
            guard !Task.isCancelled else { return }
            scrollPosition = selection
        }
        .onChange(of: scrollPosition) { _, itemID in
            guard let itemID else { return }
            guard selectableItemIDs.contains(itemID) else {
                withAnimation(.snappy(duration: selectionAnimationDuration)) {
                    scrollPosition = selection
                }
                return
            }
            selection = itemID
        }
        .onChange(of: selection) { _, itemID in
            guard scrollPosition != itemID else { return }
            withAnimation(.snappy(duration: selectionAnimationDuration)) {
                scrollPosition = itemID
            }
        }
    }

    @ViewBuilder
    private func carousel(in proxy: GeometryProxy) -> some View {
        let content = ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: spacing) {
                ForEach(helperItems) { item in
                    itemButton(item, viewportWidth: proxy.size.width)
                }
                if !selectionItems.isEmpty {
                    HStack(alignment: .top, spacing: spacing) {
                        ForEach(selectionItems) { item in
                            itemButton(item, viewportWidth: proxy.size.width)
                                .id(item.id)
                        }
                    }
                    .scrollTargetLayout()
                }
            }
            // Helpers occupy the leading centering margin, without extending
            // the scrollable range before the first selectable value.
            .padding(.leading, selectionItems.isEmpty ? 0 : -helperWidth)
        }
        .contentMargins(
            .horizontal,
            max(0, (proxy.size.width - itemWidth) / 2),
            for: .scrollContent
        )
        .scrollIndicators(.hidden)
        .scrollTargetBehavior(.viewAligned(limitBehavior: .never))
        .scrollBounceBehavior(.basedOnSize)
        .scrollPosition(id: $scrollPosition, anchor: .center)
        .coordinateSpace(name: coordinateSpaceName)

        content.horizontalScrollFades(width: AppSpacing.large)
    }

    private func itemButton(
        _ item: CenteredSelectionCarouselItem<ID>,
        viewportWidth: CGFloat
    ) -> some View {
        let isSelected = item.isSelectionTarget && selection == item.id

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
            withAnimation(.snappy(duration: selectionAnimationDuration)) {
                scrollPosition = item.id
                selection = item.id
            }
        } label: {
            VStack(spacing: 6) {
                itemIcon(item, isSelected: isSelected)
                compactTitle(item, viewportWidth: viewportWidth)
            }
            .frame(width: itemWidth)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.accessibilityLabel)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .animation(.snappy(duration: selectionAnimationDuration), value: isSelected)
    }

    private func compactTitle(
        _ item: CenteredSelectionCarouselItem<ID>,
        viewportWidth: CGFloat
    ) -> some View {
        Text(item.title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(item.color)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(width: max(96, itemWidth * 2.4), height: 16)
            .visualEffect { content, geometry in
                content.opacity(
                    compactTitleOpacity(
                        itemCenter: geometry.frame(in: .named(coordinateSpaceName)).midX,
                        viewportWidth: viewportWidth
                    )
                )
            }
    }

    private func compactTitleOpacity(
        itemCenter: CGFloat,
        viewportWidth: CGFloat
    ) -> CGFloat {
        let distance = abs(itemCenter - viewportWidth / 2)
        let normalizedDistance = distance / (itemWidth + spacing)
        let fadeStart: CGFloat = 0.15
        let fadeEnd: CGFloat = 0.42

        guard normalizedDistance > fadeStart else { return 1 }
        guard normalizedDistance < fadeEnd else { return 0 }
        return (fadeEnd - normalizedDistance) / (fadeEnd - fadeStart)
    }

    private func itemIcon(
        _ item: CenteredSelectionCarouselItem<ID>,
        isSelected: Bool
    ) -> some View {
        AppIcon(item.iconName, size: 21)
            .foregroundStyle(AppColor.iconForeground(for: item.color))
            .frame(width: iconContainerSize, height: iconContainerSize)
            .background(
                item.color.opacity(0.12),
                in: RoundedRectangle(cornerRadius: min(14, iconContainerSize * 0.3))
            )
            .overlay(alignment: .bottomTrailing) {
                if isSelected,
                   let accessoryIcon = item.selectedAccessoryIcon {
                    AppIcon(accessoryIcon, size: 9)
                        .foregroundStyle(AppColor.foreground(on: item.color))
                        .frame(width: 18, height: 18)
                        .background(item.color, in: Circle())
                        .overlay {
                            Circle()
                                .stroke(AppColor.background, lineWidth: 2)
                        }
                        .offset(x: 5, y: 5)
                        .transition(.scale.combined(with: .opacity))
                        .accessibilityHidden(true)
                }
            }
    }

    private var selectableItemIDs: Set<ID> {
        Set(selectionItems.map(\.id))
    }

    private var selectionItems: [CenteredSelectionCarouselItem<ID>] {
        items.filter(\.isSelectionTarget)
    }

    private var helperItems: [CenteredSelectionCarouselItem<ID>] {
        items.filter { !$0.isSelectionTarget }
    }

    private var helperWidth: CGFloat {
        CGFloat(helperItems.count) * (itemWidth + spacing)
    }

    private var selectionAnimationDuration: TimeInterval {
        0.10
    }

    private var itemWidth: CGFloat { 44 }
    private var spacing: CGFloat { 2 }
    private var iconContainerSize: CGFloat { 44 }
    private var coordinateSpaceName: String { "CenteredSelectionCarousel" }

    static var preferredHeight: CGFloat {
        68
    }
}
