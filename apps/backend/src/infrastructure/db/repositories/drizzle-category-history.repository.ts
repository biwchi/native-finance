import { and, desc, eq, isNotNull } from "drizzle-orm";

import type { CategoryHistoryRepository } from "../../../application/categories/category-history.repository.ts";
import type { Database } from "../client.ts";
import { transactions } from "../schema/transaction.schema.ts";

export function createDrizzleCategoryHistoryRepository(
  database: Database,
): CategoryHistoryRepository {
  return {
    async findRecent(kind, limit) {
      const rows = await database
        .select({
          categoryId: transactions.categoryId,
          note: transactions.note,
          createdAt: transactions.createdAt,
        })
        .from(transactions)
        .where(and(
          eq(transactions.kind, kind),
          isNotNull(transactions.categoryId),
          isNotNull(transactions.note),
        ))
        .orderBy(desc(transactions.createdAt))
        .limit(limit);

      return rows.filter(
        (row): row is { categoryId: string; note: string; createdAt: Date } =>
          Boolean(row.categoryId && row.note),
      );
    },
  };
}
