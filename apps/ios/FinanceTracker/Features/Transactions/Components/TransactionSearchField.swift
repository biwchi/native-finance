import SwiftUI

struct TransactionSearchField: View {
    @Binding var text: String
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: AppSpacing.small) {
            AppIcon("search", size: 18)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            TextField("Merchant, category or amount", text: $text)
                .textFieldStyle(.plain)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($isFocused)
                .onSubmit { isFocused = false }
                .accessibilityLabel("Search transactions")

            if !text.isEmpty {
                Button {
                    text = ""
                    isFocused = true
                } label: {
                    AppIcon("xmark", size: 16)
                        .foregroundStyle(.secondary)
                        .frame(width: AppControlSize.minimumTapTarget, height: AppControlSize.minimumTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .frame(minHeight: AppControlSize.minimumTapTarget)
        .padding(.leading, AppSpacing.medium)
        .padding(.trailing, text.isEmpty ? AppSpacing.medium : 4)
        .accountSelectorGlass()
        .contentShape(Capsule())
        .onTapGesture { isFocused = true }
    }
}
