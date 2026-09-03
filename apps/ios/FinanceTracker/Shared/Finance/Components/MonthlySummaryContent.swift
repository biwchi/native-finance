import SwiftUI

struct MonthlySummaryContent<Headline: View, Caption: View>: View {
    @ViewBuilder let headline: Headline
    @ViewBuilder let caption: Caption

    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            headline
            caption
                .font(.footnote)
                .foregroundStyle(contrast == .increased ? .primary : .secondary)
                .monospacedDigit()
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}
