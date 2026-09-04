export const HISTORY_CONFIDENCE_THRESHOLD = 0.5;

const MILLISECONDS_PER_YEAR = 365 * 24 * 60 * 60 * 1_000;

export type HistoryMatch = {
  categoryId: string;
  similarity: number;
  createdAt: Date;
};

export type CategorySuggestion = {
  categoryId: string;
  score: number;
  source: "exact_history" | "fuzzy_history";
};

export function normalizeTransactionDescription(value: string): string {
  return value
    .normalize("NFKD")
    .replace(/\p{M}/gu, "")
    .toLocaleLowerCase("en-US")
    .replace(/&/g, " and ")
    .replace(/[^a-z0-9]+/g, " ")
    .trim()
    .replace(/\s+/g, " ");
}

export function rankHistoryMatches(
  matches: readonly HistoryMatch[],
  now: Date = new Date(),
): CategorySuggestion[] {
  if (matches.length === 0) return [];

  const weights = new Map<string, { total: number; maximumSimilarity: number }>();
  let totalWeight = 0;

  for (const match of matches) {
    const age = Math.max(0, now.getTime() - match.createdAt.getTime());
    const recencyWeight = 0.5 ** (age / MILLISECONDS_PER_YEAR);
    const weight = match.similarity ** 2 * recencyWeight;
    const current = weights.get(match.categoryId) ?? {
      total: 0,
      maximumSimilarity: 0,
    };
    current.total += weight;
    current.maximumSimilarity = Math.max(current.maximumSimilarity, match.similarity);
    weights.set(match.categoryId, current);
    totalWeight += weight;
  }

  if (totalWeight === 0) return [];

  return [...weights.entries()]
    .map(([categoryId, value]) => ({
      categoryId,
      score: roundScore(value.maximumSimilarity * (value.total / totalWeight)),
      source: "fuzzy_history" as const,
    }))
    .filter((suggestion) => suggestion.score >= HISTORY_CONFIDENCE_THRESHOLD)
    .sort((left, right) => right.score - left.score)
    .slice(0, 3);
}

export function trigramSimilarity(left: string, right: string): number {
  const leftTrigrams = trigrams(normalizeTransactionDescription(left));
  const rightTrigrams = trigrams(normalizeTransactionDescription(right));
  if (leftTrigrams.size === 0 || rightTrigrams.size === 0) return 0;

  let intersection = 0;
  for (const trigram of leftTrigrams) {
    if (rightTrigrams.has(trigram)) intersection += 1;
  }
  return (2 * intersection) / (leftTrigrams.size + rightTrigrams.size);
}

function trigrams(value: string): Set<string> {
  const result = new Set<string>();
  for (const word of value.split(" ").filter(Boolean)) {
    const padded = `  ${word} `;
    for (let index = 0; index <= padded.length - 3; index += 1) {
      result.add(padded.slice(index, index + 3));
    }
  }
  return result;
}

function roundScore(value: number): number {
  return Math.round(value * 10_000) / 10_000;
}
