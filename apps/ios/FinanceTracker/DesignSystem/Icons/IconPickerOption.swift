import SwiftUI

struct IconPickerOption: Identifiable, Hashable {
    let symbol: String
    let title: String
    let suggestionTerms: [String]

    init(symbol: String, title: String, suggestionTerms: [String] = []) {
        self.symbol = symbol
        self.title = title
        self.suggestionTerms = suggestionTerms
    }

    var id: String { symbol }

    func matchesSuggestion(_ query: String) -> Bool {
        let normalizedQuery = Self.normalized(query)
        guard !normalizedQuery.isEmpty else { return false }
        return ([title] + suggestionTerms).contains {
            Self.normalized($0).contains(normalizedQuery)
        }
    }

    private static func normalized(_ value: String) -> String {
        value
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}
