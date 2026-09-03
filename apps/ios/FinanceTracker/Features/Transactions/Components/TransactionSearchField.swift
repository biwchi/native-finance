import SwiftUI

struct TransactionSearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: AppSpacing.small) {
            AppIcon("search", size: 18)
                .foregroundStyle(.secondary)

            TextField("Merchant, category or amount", text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .accessibilityLabel("Search transactions")

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    AppIcon("xmark", size: 16)
                        .frame(width: AppControlSize.minimumTapTarget, height: AppControlSize.minimumTapTarget)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Clear search")
            }
        }
        .frame(minHeight: AppControlSize.minimumTapTarget)
        .padding(.horizontal, AppSpacing.medium)
        .background(
            AppColor.elevatedSurface,
            in: RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
        )
    }
}
