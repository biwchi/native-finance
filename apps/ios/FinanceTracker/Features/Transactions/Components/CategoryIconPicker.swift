import SwiftUI

struct CategoryIconPicker: View {
    @Binding var selection: String
    let color: CategoryColor
    @State private var selectedGroupID: String

    init(selection: Binding<String>, color: CategoryColor) {
        _selection = selection
        self.color = color
        _selectedGroupID = State(
            initialValue: CategoryIconCatalog.group(containing: selection.wrappedValue)?.id
                ?? CategoryIconCatalog.groups[0].id
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(CategoryIconCatalog.groups) { group in
                        groupButton(group)
                    }
                }
                .padding(.horizontal, 1)
            }
            .scrollIndicators(.hidden)

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 40), spacing: 12)],
                spacing: 12
            ) {
                ForEach(selectedGroup.icons) { option in
                    iconButton(option)
                }
            }
            .id(selectedGroup.id)
        }
        .padding(.vertical, 4)
        .onChange(of: selection) { _, newSelection in
            if let group = CategoryIconCatalog.group(containing: newSelection) {
                selectedGroupID = group.id
            }
        }
    }

    private var selectedGroup: CategoryIconGroup {
        CategoryIconCatalog.groups.first { $0.id == selectedGroupID }
            ?? CategoryIconCatalog.groups[0]
    }

    private func groupButton(_ group: CategoryIconGroup) -> some View {
        let isSelected = group.id == selectedGroupID

        return Button {
            withAnimation(.snappy) {
                selectedGroupID = group.id
            }
        } label: {
            Label(group.title, icon: group.symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isSelected ? color.selectionForegroundColor : .primary)
                .padding(.horizontal, 12)
                .frame(height: 34)
                .background(
                    isSelected ? color.swiftUIColor : Color.secondary.opacity(0.12),
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func iconButton(_ option: CategoryIconOption) -> some View {
        let isSelected = AppIcons.canonicalName(selection) == option.symbol

        return Button {
            selection = option.symbol
        } label: {
            AppIcon(option.symbol, size: 17)
                .foregroundStyle(isSelected ? color.selectionForegroundColor : color.swiftUIColor)
                .frame(width: 40, height: 40)
                .background(
                    isSelected ? color.swiftUIColor : Color.secondary.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 11)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
