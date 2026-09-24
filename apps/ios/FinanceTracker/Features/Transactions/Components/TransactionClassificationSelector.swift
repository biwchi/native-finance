import SwiftUI

struct TransactionClassificationSelector: View {
    let mode: QuickTransactionMode
    let destinationItems: [CenteredSelectionCarouselItem<UUID>]
    @Binding var destinationSelection: UUID?
    let categoryItems: [CenteredSelectionCarouselItem<QuickCategoryCarouselID>]
    let expandedCategoryID: UUID?
    let expandedCategoryItems: [CenteredSelectionCarouselItem<QuickCategoryCarouselID>]?
    @Binding var categorySelection: QuickCategoryCarouselID?

    @ViewBuilder
    var body: some View {
        if mode == .transfer {
            CenteredSelectionCarousel(
                items: destinationItems,
                selection: $destinationSelection
            )
        } else {
            ZStack {
                if let expandedCategoryItems {
                    categoryCarousel(items: expandedCategoryItems)
                    .id(expandedCategoryID)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                    categoryCarousel(items: categoryItems)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .frame(height: CenteredSelectionCarousel<QuickCategoryCarouselID>.preferredHeight)
            .clipped()
            .animation(.snappy(duration: 0.3), value: expandedCategoryID)
        }
    }

    private func categoryCarousel(
        items: [CenteredSelectionCarouselItem<QuickCategoryCarouselID>]
    ) -> some View {
        CenteredSelectionCarousel(
            items: items,
            selection: $categorySelection
        )
    }
}
