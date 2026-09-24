import SwiftUI

struct CurrencyPickerRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let code: String
    let name: String
    let rate: Decimal?
    let baseCurrency: String
    let isSelected: Bool
    let isFavorite: Bool
    let select: () -> Void
    let toggleFavorite: () -> Void

    var body: some View {
        HStack(spacing: AppSpacing.small) {
            Button(action: select) {
                rowContent
                    .padding(.vertical, AppSpacing.medium)
                    .padding(.leading, AppSpacing.large)
                    .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(code), \(name)")
            .accessibilityValue(isSelected ? "Selected" : spokenRate)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .accessibilityIdentifier("currency-\(code)")

            AccentSelectionButton(
                isFavorite ? "Remove \(code) from favorites" : "Add \(code) to favorites",
                isSelected: isFavorite, iconName: "star", appearance: .icon,
                action: toggleFavorite
            )
            .accessibilityIdentifier("favoriteCurrency-\(code)")
            .padding(.trailing, AppSpacing.medium)
        }
        .background(AppColor.elevatedSurface, in: RoundedRectangle(cornerRadius: AppRadius.large))
        .overlay {
            RoundedRectangle(cornerRadius: AppRadius.large)
                .strokeBorder(isSelected ? AppColor.accent.opacity(0.5) : .clear, lineWidth: 1)
                .allowsHitTesting(false)
        }
    }

    private var rowContent: some View {
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            HStack(alignment: .center, spacing: AppSpacing.medium) {
                VStack(alignment: .leading, spacing: AppSpacing.extraSmall) {
                    HStack(spacing: AppSpacing.small) {
                        Text(code)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        if isSelected {
                            AccentSelectionButton.Indicator(isSelected: true)
                        }
                    }
                    Text(name)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if !dynamicTypeSize.isAccessibilitySize {
                    rateLabel
                }
            }
            if dynamicTypeSize.isAccessibilitySize, !isSelected {
                rateLabel
            }
        }
    }

    @ViewBuilder
    private var rateLabel: some View {
        if !isSelected {
            Text(rate.map(Self.formattedRate) ?? "Unavailable")
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    private var spokenRate: String {
        guard let rate else { return "Exchange rate unavailable" }
        return "1 \(baseCurrency) equals \(rate.formatted(.number.precision(.significantDigits(1...4)))) \(code)"
    }

    static func formattedRate(_ rate: Decimal) -> String {
        rate.formatted(.number.precision(.significantDigits(1...4)).locale(Locale(identifier: "fr_FR")))
            .replacingOccurrences(of: "\u{202F}", with: " ")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
    }
}
