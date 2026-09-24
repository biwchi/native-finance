import SwiftUI

struct CategorySearchField: View {
    @Binding var query: String
    var isFocused: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: 10) {
            AppIcon("search", size: 20)
                .foregroundStyle(.secondary)

            TextField("Search categories", text: $query)
                .textFieldStyle(.plain)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused(isFocused)
                .onSubmit { isFocused.wrappedValue = false }
                .accessibilityLabel("Search categories")

            if !query.isEmpty {
                Button {
                    query = ""
                    isFocused.wrappedValue = true
                } label: {
                    AppIcon("xmark", size: 16)
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.leading, 18)
        .padding(.trailing, query.isEmpty ? 18 : 4)
        .frame(minHeight: 54)
        .accountSelectorGlass()
        .contentShape(Capsule())
        .onTapGesture { isFocused.wrappedValue = true }
    }
}
