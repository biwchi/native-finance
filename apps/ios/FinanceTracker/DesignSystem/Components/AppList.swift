import SwiftUI

struct AppList<Content: View>: View {
    var usesCompactTopSpacing = false
    var usesScrollEdgeFades = true
    @ViewBuilder let content: Content

    var body: some View {
        List {
            content
        }
        .legacyListAppearance(usesCompactTopSpacing: usesCompactTopSpacing)
        .scrollEdgeFades(enabled: usesScrollEdgeFades)
    }
}
