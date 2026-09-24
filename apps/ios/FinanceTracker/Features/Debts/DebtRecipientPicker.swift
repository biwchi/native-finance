import SwiftUI

struct DebtRecipientPicker: View {
    private enum ItemID: Hashable {
        case all
        case recipient(UUID)
    }

    @EnvironmentObject private var transactionStore: TransactionStore
    @Binding var selection: UUID?
    @State private var isShowingRecipients = false

    var body: some View {
        CenteredSelectionCarousel(items: items, selection: carouselSelection)
            .accessibilityIdentifier("debtRecipientCarousel")
            .appSheet(isPresented: $isShowingRecipients) {
                DebtRecipientsView(selection: $selection)
            }
    }

    private var carouselSelection: Binding<ItemID?> {
        Binding(
            get: { selection.map(ItemID.recipient) },
            set: { item in
                if case let .recipient(id) = item { selection = id }
            }
        )
    }

    private var items: [CenteredSelectionCarouselItem<ItemID>] {
        [CenteredSelectionCarouselItem(
            id: .all,
            title: "All",
            iconName: "list",
            color: AppColor.accent,
            accessibilityLabel: "All recipients, choose or create a recipient",
            action: { isShowingRecipients = true }
        )] + transactionStore.debts.map { debt in
            CenteredSelectionCarouselItem(
                id: .recipient(debt.id),
                title: debt.name,
                iconName: debt.icon ?? "user",
                color: (debt.color ?? .blue).swiftUIColor,
                selectedAccessoryIcon: "check"
            )
        }
    }
}
