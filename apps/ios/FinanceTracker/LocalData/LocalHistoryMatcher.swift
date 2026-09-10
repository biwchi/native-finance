import Foundation

enum LocalHistoryMatcher {
    static func normalize(_ value: String) -> String {
        value.decomposedStringWithCompatibilityMapping.folding(options: .diacriticInsensitive, locale: Locale(identifier: "en_US"))
            .lowercased().replacingOccurrences(of: "&", with: " and ")
            .replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
    }
    static func similarity(_ left: String, _ right: String) -> Double {
        func trigrams(_ value: String) -> Set<String> {
            var result = Set<String>()
            for word in normalize(value).split(separator: " ") {
                let chars = Array("  \(word) ")
                if chars.count >= 3 { for i in 0...(chars.count - 3) { result.insert(String(chars[i..<(i+3)])) } }
            }
            return result
        }
        let a = trigrams(left), b = trigrams(right)
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        return 2 * Double(a.intersection(b).count) / Double(a.count + b.count)
    }
    static func suggestions(description: String, kind: TransactionKind, transactions: [FinanceTransaction], now: Date = .now) -> [CategorySuggestion] {
        let normalized = normalize(description)
        guard !normalized.isEmpty else { return [] }
        let history = transactions.filter { $0.kind == kind && $0.category != nil && $0.note != nil }.sorted { $0.createdAt > $1.createdAt }.prefix(500)
        if let exact = history.first(where: { normalize($0.note!) == normalized }), let id = exact.category?.id { return [CategorySuggestion(categoryId: id, score: 1, source: "exact_history")] }
        var weights: [UUID: (weight: Double, similarity: Double)] = [:]
        var total = 0.0
        for item in history {
            let score = similarity(normalized, item.note!)
            let weight = score * score * pow(0.5, max(0, now.timeIntervalSince(item.createdAt)) / (365 * 24 * 60 * 60))
            let previous = weights[item.category!.id] ?? (0,0)
            weights[item.category!.id] = (previous.weight + weight, max(previous.similarity, score)); total += weight
        }
        guard total > 0 else { return [] }
        return weights.map { CategorySuggestion(categoryId: $0.key, score: ($0.value.similarity * $0.value.weight / total * 10000).rounded() / 10000, source: "fuzzy_history") }.filter { $0.score >= 0.5 }.sorted { $0.score > $1.score }.prefix(3).map { $0 }
    }
}
