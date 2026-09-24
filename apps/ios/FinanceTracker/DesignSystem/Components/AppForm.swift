import SwiftUI

struct AppForm<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        AppList { content }
            .environment(\.defaultMinListRowHeight, AppControlSize.formRowMinimumHeight)
            .environment(\.usesFormLayout, true)
    }
}

extension EnvironmentValues {
    @Entry var usesFormLayout = false
}
