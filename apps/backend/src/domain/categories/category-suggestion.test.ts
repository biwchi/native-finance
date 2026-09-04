import { describe, expect, it } from "bun:test";

import {
  normalizeTransactionDescription,
  rankHistoryMatches,
  trigramSimilarity,
} from "./category-suggestion.ts";

describe("category resolution", () => {
  it("normalizes punctuation, spacing, accents, and ampersands", () => {
    expect(normalizeTransactionDescription("  Café &   BAKERY! ")).toBe(
      "cafe and bakery",
    );
  });

  it("gives close typos a stronger trigram score than unrelated text", () => {
    const typo = trigramSimilarity("north fuel staton", "north fuel station");
    const unrelated = trigramSimilarity("north fuel staton", "monthly salary");

    expect(typo).toBeGreaterThan(0.8);
    expect(typo).toBeGreaterThan(unrelated);
  });

  it("combines nearby history into a category vote", () => {
    const now = new Date("2026-08-31T12:00:00.000Z");
    const suggestions = rankHistoryMatches(
      [
        {
          categoryId: "fuel",
          similarity: 0.92,
          createdAt: new Date("2026-08-30T12:00:00.000Z"),
        },
        {
          categoryId: "fuel",
          similarity: 0.84,
          createdAt: new Date("2026-08-20T12:00:00.000Z"),
        },
        {
          categoryId: "transport",
          similarity: 0.7,
          createdAt: new Date("2026-08-29T12:00:00.000Z"),
        },
      ],
      now,
    );

    expect(suggestions[0]?.categoryId).toBe("fuel");
    expect(suggestions[0]?.source).toBe("fuzzy_history");
    expect(suggestions[0]?.score).toBeGreaterThanOrEqual(0.5);
  });

  it("returns no answer for evenly conflicting history", () => {
    const createdAt = new Date("2026-08-31T12:00:00.000Z");
    const suggestions = rankHistoryMatches([
      { categoryId: "food", similarity: 0.9, createdAt },
      { categoryId: "fuel", similarity: 0.9, createdAt },
    ]);

    expect(suggestions).toEqual([]);
  });

  it("returns no answer when no history is supplied", () => {
    expect(rankHistoryMatches([])).toEqual([]);
  });
});
