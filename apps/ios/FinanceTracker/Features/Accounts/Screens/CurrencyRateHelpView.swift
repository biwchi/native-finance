import SwiftUI

struct CurrencyRateHelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            AppList {
                AppSection {
                    answer("How often are rates updated?",
                           "The app checks for new rates when you use it, once the last successful refresh is at least 24 hours old. Rates are not live and may stay the same between updates.")
                    answer("What does the updated time mean?",
                           "It shows when the saved rate table was fetched. Individual currencies can have an earlier rate date.")
                    answer("What happens when I'm offline?",
                           "Your last saved rates stay available. If an update fails, the app keeps them and tries again when it can connect. Currencies without a saved rate show Unavailable.")
                    answer("How do I read the rates?",
                           "Each amount shows how much of that currency equals 1 unit of your selected currency. Rates are rounded for display. Your bank or card provider may use a different rate or add fees.")
                }
            }
            .navigationTitle("Exchange rates")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: { AppIcon("xmark", size: AppControlSize.iconButtonGlyph) }
                        .accessibilityLabel("Close exchange rate help")
                        .legacyToolbarIcon()
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func answer(_ question: String, _ response: String) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            Text(question)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            Text(response)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, AppSpacing.extraSmall)
    }
}
