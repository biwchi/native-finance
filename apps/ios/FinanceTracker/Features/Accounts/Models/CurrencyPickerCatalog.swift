import Foundation

struct CurrencyPickerCatalog {
    let selected: [String]
    let favorites: [String]
    let others: [String]

    var isEmpty: Bool { selected.isEmpty && favorites.isEmpty && others.isEmpty }

    init(currencyCodes: [String], selection: String, favorites: Set<String>, query: String,
         locale: Locale = .current) {
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let currentCodes = Set(Locale.commonISOCurrencyCodes)
        let codes = Set(currencyCodes + [selection]).filter { code in
            guard !code.isEmpty else { return false }
            if search.isEmpty {
                // Keep saved choices visible. Historical codes remain available through search.
                return currentCodes.contains(code) || code == selection || favorites.contains(code)
            }
            return code.localizedCaseInsensitiveContains(search)
                || locale.localizedString(forCurrencyCode: code)?.localizedCaseInsensitiveContains(search) == true
        }.sorted()

        selected = codes.filter { $0 == selection }
        self.favorites = codes.filter { $0 != selection && favorites.contains($0) }
        others = codes.filter { $0 != selection && !favorites.contains($0) }
    }
}
