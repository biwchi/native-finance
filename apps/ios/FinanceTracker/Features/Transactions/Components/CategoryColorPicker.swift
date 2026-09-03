import SwiftUI

struct CategoryColorPicker: View {
    @Binding var selection: CategoryColor

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 34), spacing: 12)],
            spacing: 12
        ) {
            ForEach(CategoryColor.allCases) { choice in
                Button {
                    selection = choice
                } label: {
                    Circle()
                        .fill(choice.swiftUIColor)
                        .frame(width: 34, height: 34)
                        .overlay {
                            if selection == choice {
                                AppIcon("check", size: 12)
                                    .foregroundStyle(choice.selectionForegroundColor)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(choice.title)
                .accessibilityAddTraits(selection == choice ? .isSelected : [])
            }
        }
        .padding(.vertical, 4)
    }
}
