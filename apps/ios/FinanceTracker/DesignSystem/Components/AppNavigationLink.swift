import SwiftUI

/// Declare the legacy back toolbar with the destination, before its first frame.
struct AppNavigationLink<Label: View, Destination: View>: View {
    private let destination: () -> Destination
    private let label: () -> Label

    init(@ViewBuilder destination: @escaping () -> Destination, @ViewBuilder label: @escaping () -> Label) {
        self.destination = destination
        self.label = label
    }

    var body: some View {
        NavigationLink {
            destination().legacyNavigationDestination()
        } label: {
            label()
        }
    }
}

extension AppNavigationLink where Label == Text {
    init(_ title: LocalizedStringKey, @ViewBuilder destination: @escaping () -> Destination) {
        self.init(destination: destination, label: { Text(title) })
    }
}
