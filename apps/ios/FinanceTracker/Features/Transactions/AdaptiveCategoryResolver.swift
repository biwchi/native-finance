import Foundation
import NaturalLanguage

#if canImport(FoundationModels)
import FoundationModels
#endif

enum CategoryResolutionSource: String, Equatable {
    case exactHistory
    case fuzzyHistory
    case seed
    case embedding
    case foundationModel
}

struct CategoryResolution: Equatable {
    let categoryID: UUID
    let confidence: Double
    let source: CategoryResolutionSource
}

protocol CategoryResolving {
    func resolve(
        description: String,
        kind: TransactionKind,
        categories: [TransactionCategory]
    ) async -> CategoryResolution?
}

struct AdaptiveCategoryResolver: CategoryResolving {
    private let apiClient: APIClient

    init(apiClient: APIClient = APIClient()) {
        self.apiClient = apiClient
    }

    func resolve(
        description: String,
        kind: TransactionKind,
        categories: [TransactionCategory]
    ) async -> CategoryResolution? {
        let availableCategories = categories.filter { $0.kind == kind }
        guard !availableCategories.isEmpty else { return nil }

        if let history = try? await apiClient.categorySuggestions(
            description: description,
            kind: kind
        ).suggestions.first,
           availableCategories.contains(where: { $0.id == history.categoryId }) {
            return CategoryResolution(
                categoryID: history.categoryId,
                confidence: history.score,
                source: history.source == "exact_history" ? .exactHistory : .fuzzyHistory
            )
        }

        if let local = LocalCategoryMatcher.resolve(
            description: description,
            categories: availableCategories
        ) {
            return local
        }

#if canImport(FoundationModels)
        if CategoryModelGate.isEnabled, #available(iOS 26.0, *) {
            return await FoundationCategoryResolver.resolve(
                description: description,
                categories: availableCategories
            )
        }
#endif

        return nil
    }
}

enum CategoryModelGate {
    static var isEnabled: Bool {
        Bundle.main.object(forInfoDictionaryKey: "FOUNDATION_CATEGORY_RESOLVER_ENABLED") as? Bool ?? false
    }
}

enum LocalCategoryMatcher {
    private static let fuzzyThreshold = 0.72
    private static let fuzzyMargin = 0.08
    private static let embeddingDistanceThreshold = 0.92
    private static let embeddingDistanceMargin = 0.08
    private static let stopWords: Set<String> = [
        "and", "for", "from", "the", "with", "into", "this", "that",
    ]

    static func resolve(
        description: String,
        categories: [TransactionCategory]
    ) -> CategoryResolution? {
        if let lexical = resolveLexically(
            description: description,
            categories: categories
        ) {
            return lexical
        }

        return resolveSemantically(
            description: description,
            categories: categories
        )
    }

    static func resolveLexically(
        description: String,
        categories: [TransactionCategory]
    ) -> CategoryResolution? {
        let normalizedDescription = normalize(description)
        guard !normalizedDescription.isEmpty else { return nil }

        if let exact = exactMatch(
            description: normalizedDescription,
            categories: categories
        ) {
            return exact
        }

        return fuzzyMatch(
            description: normalizedDescription,
            categories: categories
        )
    }

    static func resolveSemantically(
        description: String,
        categories: [TransactionCategory]
    ) -> CategoryResolution? {
        let normalizedDescription = normalize(description)
        guard !normalizedDescription.isEmpty else { return nil }
        return embeddingMatch(
            description: normalizedDescription,
            categories: categories
        )
    }

    static func normalize(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US"))
            .lowercased()
            .replacingOccurrences(of: "&", with: " and ")
            .replacingOccurrences(
                of: #"[^a-z0-9]+"#,
                with: " ",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"\s+"#,
                with: " ",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func trigramSimilarity(_ left: String, _ right: String) -> Double {
        let leftTrigrams = trigrams(normalize(left))
        let rightTrigrams = trigrams(normalize(right))
        guard !leftTrigrams.isEmpty, !rightTrigrams.isEmpty else { return 0 }

        let intersection = leftTrigrams.intersection(rightTrigrams).count
        return Double(2 * intersection) / Double(leftTrigrams.count + rightTrigrams.count)
    }

    private static func exactMatch(
        description: String,
        categories: [TransactionCategory]
    ) -> CategoryResolution? {
        let paddedDescription = " \(description) "
        let matches = categories.compactMap { category -> (TransactionCategory, Double)? in
            let score = category.classificationExamples.reduce(0.0) { current, example in
                let term = normalize(example)
                guard !term.isEmpty else { return current }

                if description == term {
                    return max(current, 2)
                }
                if paddedDescription.contains(" \(term) ") {
                    return max(current, 1 + min(Double(term.count) / 100, 0.1))
                }
                return current
            }

            return score > 0 ? (category, score) : nil
        }
        .sorted { $0.1 > $1.1 }

        guard let best = matches.first else { return nil }
        if matches.count > 1, best.1 == matches[1].1 {
            return nil
        }

        return CategoryResolution(
            categoryID: best.0.id,
            confidence: 1,
            source: .seed
        )
    }

    private static func fuzzyMatch(
        description: String,
        categories: [TransactionCategory]
    ) -> CategoryResolution? {
        let matches = categories.map { category in
            let score = category.classificationExamples
                .map { trigramSimilarity(description, $0) }
                .max() ?? 0
            return (category, score)
        }
        .sorted { $0.1 > $1.1 }

        guard let best = matches.first, best.1 >= fuzzyThreshold else { return nil }
        let runnerUp = matches.dropFirst().first?.1 ?? 0
        guard best.1 - runnerUp >= fuzzyMargin else { return nil }

        return CategoryResolution(
            categoryID: best.0.id,
            confidence: best.1,
            source: .seed
        )
    }

    private static func embeddingMatch(
        description: String,
        categories: [TransactionCategory]
    ) -> CategoryResolution? {
        guard let embedding = NLEmbedding.wordEmbedding(for: .english, revision: 1) else {
            return nil
        }

        let queryTokens = tokens(description).filter {
            $0.count >= 3 && !stopWords.contains($0) && embedding.contains($0)
        }
        guard !queryTokens.isEmpty else { return nil }

        let matches = categories.compactMap { category -> (TransactionCategory, Double)? in
            let categoryTokens = Set(
                category.classificationExamples
                    .flatMap { tokens(normalize($0)) }
                    .filter { embedding.contains($0) }
            )
            guard !categoryTokens.isEmpty else { return nil }

            let distances = queryTokens.compactMap { query -> Double? in
                categoryTokens
                    .map { embedding.distance(between: query, and: $0, distanceType: .cosine) }
                    .min()
            }
            guard !distances.isEmpty else { return nil }
            return (category, distances.reduce(0, +) / Double(distances.count))
        }
        .sorted { $0.1 < $1.1 }

        guard let best = matches.first, best.1 <= embeddingDistanceThreshold else {
            return nil
        }
        let runnerUp = matches.dropFirst().first?.1 ?? 2
        guard runnerUp - best.1 >= embeddingDistanceMargin else { return nil }

        return CategoryResolution(
            categoryID: best.0.id,
            confidence: max(0, 1 - best.1 / 2),
            source: .embedding
        )
    }

    private static func tokens(_ value: String) -> [String] {
        value.split(separator: " ").map(String.init)
    }

    private static func trigrams(_ value: String) -> Set<String> {
        var result = Set<String>()
        for word in tokens(value) {
            let padded = "  \(word) "
            guard padded.count >= 3 else { continue }
            for index in 0...(padded.count - 3) {
                let start = padded.index(padded.startIndex, offsetBy: index)
                let end = padded.index(start, offsetBy: 3)
                result.insert(String(padded[start..<end]))
            }
        }
        return result
    }
}

#if canImport(FoundationModels)
@available(iOS 26.0, *)
enum FoundationCategoryResolver {
    static func resolve(
        description: String,
        categories: [TransactionCategory]
    ) async -> CategoryResolution? {
        let model = SystemLanguageModel.default
        guard
            model.isAvailable,
            model.supportsLocale(Locale(identifier: "en"))
        else {
            return nil
        }

        let uncategorized = "uncategorized"
        let choices = categories.map(\.name) + [uncategorized]
        let schema = GenerationSchema(
            type: String.self,
            description: "The best matching transaction category",
            anyOf: choices
        )
        let session = LanguageModelSession(
            model: model,
            instructions: "Choose one allowed category for an English financial transaction. Choose uncategorized when no category clearly fits."
        )

        do {
            let response = try await session.respond(
                to: description,
                schema: schema,
                options: GenerationOptions(
                    sampling: .greedy,
                    maximumResponseTokens: 12
                )
            )

            guard case let .string(name) = response.content.kind,
                  name != uncategorized,
                  let category = categories.first(where: { $0.name == name })
            else {
                return nil
            }

            return CategoryResolution(
                categoryID: category.id,
                confidence: 1,
                source: .foundationModel
            )
        } catch {
            return nil
        }
    }
}
#endif
