import SwiftUI

struct TransactionModeSwipe: ViewModifier {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @GestureState(resetTransaction: Transaction(animation: .spring(response: 0.3, dampingFraction: 0.85)))
    private var dragOffset: CGFloat = 0
    let modes: [QuickTransactionMode]
    @Binding var selection: QuickTransactionMode
    var isActive = true

    func body(content: Content) -> some View {
        content
            .environment(\.transactionSwipeOffset, dragOffset)
            .contentShape(Rectangle())
            .simultaneousGesture(
                DragGesture(minimumDistance: 10)
                    .updating($dragOffset) { value, offset, transaction in
                        guard isEnabled, isActive, !reduceMotion,
                              modes.count > 1, modes.contains(selection),
                              abs(value.translation.width) > abs(value.translation.height) * 1.5 else {
                            offset = 0
                            return
                        }
                        transaction.animation = nil
                        // Rubber-band resistance approaches 24 points, even on a long drag.
                        let distance = value.translation.width
                        offset = 24 * distance / (abs(distance) + 72)
                    }
                    .onEnded { value in
                        guard isEnabled, isActive,
                              let next = selection.selectionAfterSwipe(value.translation, among: modes) else { return }
                        selection = next
                    }
            )
    }
}
