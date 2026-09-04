import {
  normalizeTransactionDescription,
  rankHistoryMatches,
  trigramSimilarity,
  type CategorySuggestion,
} from "../../domain/categories/category-suggestion.ts";
import type { TransactionKind } from "../../domain/categories/category.ts";
import type { CategoryHistoryRepository } from "./category-history.repository.ts";

export async function suggestCategory(
  input: { description: string; kind: TransactionKind },
  dependencies: { history: CategoryHistoryRepository },
): Promise<{ suggestions: CategorySuggestion[] }> {
  const normalizedDescription = normalizeTransactionDescription(input.description);
  if (!normalizedDescription) return { suggestions: [] };

  const history = await dependencies.history.findRecent(input.kind, 500);
  const exact = history.find((transaction) =>
    normalizeTransactionDescription(transaction.note) === normalizedDescription
  );
  if (exact) {
    return {
      suggestions: [{
        categoryId: exact.categoryId,
        score: 1,
        source: "exact_history",
      }],
    };
  }

  return {
    suggestions: rankHistoryMatches(history.map((row) => ({
      categoryId: row.categoryId,
      similarity: trigramSimilarity(normalizedDescription, row.note),
      createdAt: row.createdAt,
    }))),
  };
}
