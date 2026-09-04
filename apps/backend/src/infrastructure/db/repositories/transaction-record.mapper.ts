import { getTableColumns } from "drizzle-orm";

import type { CategorySummary } from "../../../domain/categories/category.ts";
import type {
  RecurrenceFrequency,
  TransactionResponse,
} from "../../../domain/transactions/transaction.ts";
import { categories } from "../schema/category.schema.ts";
import { recurringSchedules } from "../schema/recurring-schedule.schema.ts";
import { transactions } from "../schema/transaction.schema.ts";

export const categorySelection = {
  id: categories.id,
  systemKey: categories.systemKey,
  name: categories.name,
  kind: categories.kind,
  parentId: categories.parentId,
  icon: categories.icon,
  color: categories.color,
  isSystem: categories.isSystem,
};

export const transactionSelection = {
  ...getTableColumns(transactions),
  category: categorySelection,
  recurrence: {
    id: recurringSchedules.id,
    frequency: recurringSchedules.frequency,
    endAt: recurringSchedules.endAt,
  },
};

type TransactionSelectionRow = typeof transactions.$inferSelect & {
  category: CategorySummary | null;
  recurrence: {
    id: string;
    frequency: RecurrenceFrequency;
    endAt: Date | null;
  } | null;
};

export function toTransactionResponse(
  row: TransactionSelectionRow,
): TransactionResponse {
  const { categoryId: _, recurringScheduleId: __, ...transaction } = row;
  return transaction;
}
