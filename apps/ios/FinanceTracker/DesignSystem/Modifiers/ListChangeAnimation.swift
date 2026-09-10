import SwiftUI

struct ListChangeAnimation<Value: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let value: Value

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: value)
    }
}

extension View {
    /// Observe identities at the List/Form level so asynchronous data updates also
    /// animate row movement and removal of an empty section's header.
    func animateListChanges<Value: Equatable>(value: Value) -> some View {
        modifier(ListChangeAnimation(value: value))
    }
}
