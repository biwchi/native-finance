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
                    CenteredSelectionCarousel(
                        items: expandedCategoryItems,
                        selection: $categorySelection
                    )
                    .id(expandedCategoryID)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                    CenteredSelectionCarousel(
                        items: categoryItems,
                        selection: $categorySelection
                    )
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .frame(height: 84)
            .clipped()
            .animation(.snappy(duration: 0.3), value: expandedCategoryID)
        }
    }
}
