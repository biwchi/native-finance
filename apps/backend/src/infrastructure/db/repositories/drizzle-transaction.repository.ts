import {
  and,
  asc,
  desc,
  eq,
  getTableColumns,
  gt,
  isNotNull,
  lte,
} from "drizzle-orm";

import type { TransactionRepository } from "../../../application/transactions/transaction.repository.ts";
import type { Database } from "../client.ts";
import { categories } from "../schema/category.schema.ts";
import { recurringSchedules } from "../schema/recurring-schedule.schema.ts";
import { transactions } from "../schema/transaction.schema.ts";
import { createDrizzleTransactionStore } from "./drizzle-transaction.store.ts";
import {
  categorySelection,
  toTransactionResponse,
  transactionSelection,
} from "./transaction-record.mapper.ts";

export function createDrizzleTransactionRepository(
  database: Database,
): TransactionRepository {
  const store = createDrizzleTransactionStore(database);

  return {
    ...store,

    async listDetailed(accountId) {
      const rows = await database.select(transactionSelection)
        .from(transactions)
        .leftJoin(categories, eq(transactions.categoryId, categories.id))
        .leftJoin(
          recurringSchedules,
          eq(transactions.recurringScheduleId, recurringSchedules.id),
        )
        .where(accountId ? eq(transactions.accountId, accountId) : undefined)
        .orderBy(desc(transactions.occurredAt), desc(transactions.createdAt));
      return rows.map(toTransactionResponse);
    },

    listSchedules(accountId) {
      return database.select({
        ...getTableColumns(recurringSchedules),
        category: categorySelection,
      })
        .from(recurringSchedules)
        .leftJoin(categories, eq(recurringSchedules.categoryId, categories.id))
        .where(accountId ? eq(recurringSchedules.accountId, accountId) : undefined);
    },

    listRecordedFuture(accountId, after) {
      return database.select({
        scheduleId: transactions.recurringScheduleId,
        occurredAt: transactions.occurredAt,
      })
        .from(transactions)
        .where(and(
          isNotNull(transactions.recurringScheduleId),
          gt(transactions.occurredAt, after),
          accountId ? eq(transactions.accountId, accountId) : undefined,
        ))
        .orderBy(asc(transactions.occurredAt))
        .then((rows) => rows.filter(
          (row): row is { scheduleId: string; occurredAt: Date } =>
            row.scheduleId !== null,
        ));
    },

    findDueSchedules(through) {
      return database.select().from(recurringSchedules).where(and(
        isNotNull(recurringSchedules.nextOccurrenceAt),
        lte(recurringSchedules.nextOccurrenceAt, through),
      ));
    },

    atomically(operation) {
      return database.transaction((transaction) =>
        operation(createDrizzleTransactionStore(transaction))
      );
    },
  };
}
