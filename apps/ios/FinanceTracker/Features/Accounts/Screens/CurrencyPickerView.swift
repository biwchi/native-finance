import SwiftUI

struct CurrencyPickerView: View {
    @Environment(\.dismiss) private var dismiss

    @Binding var selection: String
    let currencyCodes: [String]

    @State private var query = ""
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        List(filteredCurrencyCodes, id: \.self) { code in
            Button {
                selection = code
                dismiss()
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(code)
                            .font(.headline)
                            .foregroundStyle(.primary)

                        if let name = currencyName(code) {
                            Text(name)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    if selection == code {
                        AppIcon("check", size: 17)
                            .foregroundStyle(.tint)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .overlay {
            if filteredCurrencyCodes.isEmpty {
                ContentUnavailableView(
                    "No currencies found",
                    iconName: "search",
                    description: Text("No results for “\(query)”.")
                )
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            searchField
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            AppIcon("search", size: 20)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            TextField("Code or currency name", text: $query)
                .textFieldStyle(.plain)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($isSearchFocused)
                .onSubmit { isSearchFocused = false }
                .accessibilityLabel("Search currencies")

            if !query.isEmpty {
                Button {
                    query = ""
                    isSearchFocused = true
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
        .onTapGesture { isSearchFocused = true }
    }

    private var filteredCurrencyCodes: [String] {
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !search.isEmpty else {
            return currencyCodes
        }

        return currencyCodes.filter { code in
            code.localizedCaseInsensitiveContains(search) ||
                currencyName(code)?.localizedCaseInsensitiveContains(search) == true
        }
    }

    private func currencyName(_ code: String) -> String? {
        Locale.current.localizedString(forCurrencyCode: code)
    }
}
