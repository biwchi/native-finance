import { and, asc, eq, gt, ne } from "drizzle-orm";

import type { TransactionStore } from "../../../application/transactions/transaction.repository.ts";
import type { Database } from "../client.ts";
import { categories } from "../schema/category.schema.ts";
import { recurringSchedules } from "../schema/recurring-schedule.schema.ts";
import { transactions } from "../schema/transaction.schema.ts";
import {
  toTransactionResponse,
  transactionSelection,
} from "./transaction-record.mapper.ts";

type DatabaseTransaction = Parameters<
  Parameters<Database["transaction"]>[0]
>[0];

export type TransactionQueryClient = Database | DatabaseTransaction;

export function createDrizzleTransactionStore(
  client: TransactionQueryClient,
): TransactionStore {
  return {
    async findRecord(id) {
      const [transaction] = await client.select().from(transactions)
        .where(eq(transactions.id, id)).limit(1);
      return transaction ?? null;
    },

    async findDetailed(id) {
      const [transaction] = await client.select(transactionSelection)
        .from(transactions)
        .leftJoin(categories, eq(transactions.categoryId, categories.id))
        .leftJoin(
          recurringSchedules,
          eq(transactions.recurringScheduleId, recurringSchedules.id),
        )
        .where(eq(transactions.id, id)).limit(1);
      return transaction ? toTransactionResponse(transaction) : null;
    },

    async insertTransaction(values) {
      const [transaction] = await client.insert(transactions).values(values).returning();
      if (!transaction) throw new Error("Transaction insert did not return a row");
      return transaction;
    },

    insertTransactions(values) {
      return client.insert(transactions).values(values).returning();
    },

    async updateTransaction(id, values) {
      const [transaction] = await client.update(transactions).set(values)
        .where(eq(transactions.id, id)).returning({ id: transactions.id });
      return Boolean(transaction);
    },

    async deleteTransaction(id) {
      const [transaction] = await client.delete(transactions)
        .where(eq(transactions.id, id)).returning({ id: transactions.id });
      return Boolean(transaction);
    },

    async findSchedule(id, lock = false) {
      const query = client.select().from(recurringSchedules)
        .where(eq(recurringSchedules.id, id)).limit(1);
      const [schedule] = lock ? await query.for("update") : await query;
      return schedule ?? null;
    },

    async insertSchedule(values) {
      const [schedule] = await client.insert(recurringSchedules).values(values).returning();
      if (!schedule) throw new Error("Recurring schedule insert did not return a row");
      return schedule;
    },

    async updateSchedule(id, values) {
      await client.update(recurringSchedules).set(values)
        .where(eq(recurringSchedules.id, id));
    },

    async deleteSchedule(id) {
      await client.delete(recurringSchedules).where(eq(recurringSchedules.id, id));
    },

    async findFirstRecordedFuture(scheduleId, after) {
      const [transaction] = await client.select().from(transactions)
        .where(and(
          eq(transactions.recurringScheduleId, scheduleId),
          gt(transactions.occurredAt, after),
        ))
        .orderBy(asc(transactions.occurredAt)).limit(1);
      return transaction ?? null;
    },

    async findRecordedOccurrence(scheduleId, occurredAt) {
      const [transaction] = await client.select().from(transactions)
        .where(and(
          eq(transactions.recurringScheduleId, scheduleId),
          eq(transactions.occurredAt, occurredAt),
        )).limit(1);
      return transaction ?? null;
    },

    async deleteFutureTransactions(scheduleId, after, excludeId) {
      await client.delete(transactions).where(and(
        eq(transactions.recurringScheduleId, scheduleId),
        gt(transactions.occurredAt, after),
        excludeId ? ne(transactions.id, excludeId) : undefined,
      ));
    },

    async insertOccurrences(schedule, dates) {
      if (dates.length === 0) return;
      await client.insert(transactions).values(dates.map((occurredAt) => ({
        accountId: schedule.accountId,
        kind: schedule.kind,
        amount: schedule.amount,
        currency: schedule.currency,
        categoryId: schedule.categoryId,
        recurringScheduleId: schedule.id,
        merchant: schedule.merchant,
        payee: schedule.payee,
        note: schedule.note,
        occurredAt,
      }))).onConflictDoNothing();
    },
  };
}
