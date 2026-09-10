import SwiftUI

struct AppForm<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        if #available(iOS 26.0, *) {
            Form { content }
                .scrollEdgeFades()
        } else {
            // Older Form styles override row insets and header text casing.
            AppList { content }
                .listStyle(.insetGrouped)
                .environment(\.defaultMinListRowHeight, AppControlSize.formRowMinimumHeight)
                .environment(\.usesLegacyFormLayout, true)
        }
    }
}

extension EnvironmentValues {
    @Entry var usesLegacyFormLayout = false
}
