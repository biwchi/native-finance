import SwiftUI

private struct TransactionSwipeOffsetKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    var transactionSwipeOffset: CGFloat {
        get { self[TransactionSwipeOffsetKey.self] }
        set { self[TransactionSwipeOffsetKey.self] = newValue }
    }
}
