import type { TransactionKind } from "../../domain/categories/category.ts";

export type CategoryHistoryRow = {
  categoryId: string;
  note: string;
  createdAt: Date;
};

export interface CategoryHistoryRepository {
  findRecent(kind: TransactionKind, limit: number): Promise<CategoryHistoryRow[]>;
}
