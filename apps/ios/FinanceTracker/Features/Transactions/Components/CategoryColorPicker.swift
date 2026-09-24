import SwiftUI

struct CategoryColorPicker: View {
    @Binding var selection: CategoryColor

    var body: some View {
        ScrollViewReader { proxy in
            colorSwatches
                .task {
                    await Task.yield()
                    guard !Task.isCancelled else { return }
                    proxy.scrollTo(selection, anchor: .center)
                }
        }
    }

    private var colorSwatches: some View {
        ScrollView(.horizontal) {
            HStack(spacing: AppSpacing.small) {
                ForEach(CategoryColor.allCases) { choice in
                    Button {
                        selection = choice
                    } label: {
                        Circle()
                            .fill(choice.swiftUIColor)
                            .frame(width: 34, height: 34)
                            .overlay {
                                if selection == choice {
                                    AppIcon("check", size: 14)
                                        .foregroundStyle(choice.selectionForegroundColor)
                                }
                            }
                            .frame(width: AppControlSize.minimumTapTarget, height: AppControlSize.minimumTapTarget)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(choice.title)
                    .accessibilityAddTraits(selection == choice ? .isSelected : [])
                    .id(choice)
                }
            }
            .padding(.horizontal, AppSpacing.large)
        }
        .scrollIndicators(.hidden)
        .horizontalScrollFades()
        .padding(.horizontal, -AppSpacing.large)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Icon color")
    }
}
