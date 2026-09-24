import SwiftUI

struct IconPicker: View {
    @Binding var selection: String
    var groups: [IconPickerGroup] = AppIconCatalog.groups

    @ScaledMetric private var tileSize = AppControlSize.minimumTapTarget
    @ScaledMetric private var tileSpacing = AppSpacing.small

    private let fadeWidth = AppSpacing.large

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: AppSpacing.extraLarge) {
                    ForEach(groups) { group in
                        groupContent(group)
                            .id(group.id)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, AppSpacing.extraSmall)
            }
            .scrollIndicators(.hidden)
            .contentMargins(.horizontal, fadeWidth, for: .scrollContent)
            .horizontalScrollFades(width: fadeWidth)
            .task {
                await Task.yield()
                guard !Task.isCancelled, let group = selectedGroup else { return }
                proxy.scrollTo(group.id, anchor: .leading)
            }
        }
        // Keep the fades in the form's inset and align the tiles with its rows.
        .padding(.horizontal, -fadeWidth)
    }

    private var selectedGroup: IconPickerGroup? {
        groups.first { group in
            group.icons.contains { $0.symbol == AppIcons.canonicalName(selection) }
        }
    }

    private func groupContent(_ group: IconPickerGroup) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.medium) {
            Text(group.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)

            LazyHGrid(
                rows: Array(repeating: GridItem(.fixed(tileSize), spacing: tileSpacing), count: 4),
                spacing: tileSpacing
            ) {
                ForEach(group.icons) { option in
                    iconButton(option)
                }
            }
            .frame(height: tileSize * 4 + tileSpacing * 3)
        }
    }

    private func iconButton(_ option: IconPickerOption) -> some View {
        let isSelected = AppIcons.canonicalName(selection) == option.symbol

        return AccentSelectionButton(
            option.title,
            isSelected: isSelected,
            iconName: option.symbol,
            appearance: .icon
        ) {
            selection = option.symbol
        }
    }
}
