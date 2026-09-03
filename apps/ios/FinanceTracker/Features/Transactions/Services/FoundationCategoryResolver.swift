import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

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
