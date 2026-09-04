import {
  boundExistingNext,
  boundedNextOccurrence,
} from "../../domain/transactions/recurrence.ts";
import type {
  TransactionInput,
  TransactionResponse,
  TransactionValidationError,
} from "../../domain/transactions/transaction.ts";
import { error, ok, type Result } from "../../domain/shared/result.ts";
import type { AccountRepository } from "../accounts/account.repository.ts";
import type { CategoryRepository } from "../categories/category.repository.ts";
import { materializeRecurringSchedule } from "./materialize-recurring-schedule.ts";
import { prepareTransaction } from "./prepare-transaction.ts";
import { scheduleTemplate } from "./recurring-values.ts";
import type { TransactionRepository } from "./transaction.repository.ts";

type UpdateTransactionError =
  | "transaction_not_found"
  | TransactionValidationError;

export async function updateTransaction(
  input: { id: string; transaction: TransactionInput },
  dependencies: {
    accounts: AccountRepository;
    categories: CategoryRepository;
    transactions: TransactionRepository;
  },
): Promise<Result<TransactionResponse, UpdateTransactionError>> {
  const existing = await dependencies.transactions.findRecord(input.id);
  if (!existing) return error("transaction_not_found", "Transaction not found");

  const prepared = await prepareTransaction(input.transaction, dependencies);
  if (!prepared.ok) return prepared;
  const { recurrence } = prepared.value;

  const values = {
    ...prepared.value.values,
    currency: existing.accountId === input.transaction.accountId
      ? existing.currency
      : prepared.value.values.currency,
    updatedAt: new Date(),
  };

  const scheduleId = await dependencies.transactions.atomically(async (store) => {
    if (!recurrence) {
      const updated = await store.updateTransaction(input.id, values);
      if (existing.recurringScheduleId) {
        await store.deleteSchedule(existing.recurringScheduleId);
      }
      return updated ? null : undefined;
    }

    if (existing.recurringScheduleId) {
      const schedule = await store.findSchedule(existing.recurringScheduleId, true);
      if (!schedule) throw new Error("Recurring schedule not found");
      const frequencyChanged = schedule.frequency !== recurrence.frequency;
      const nextOccurrenceAt = frequencyChanged || !schedule.nextOccurrenceAt
        ? boundedNextOccurrence(
            schedule.lastOccurrenceAt,
            schedule.startAt,
            recurrence.frequency,
            recurrence.endAt,
          )
        : boundExistingNext(schedule.nextOccurrenceAt, recurrence.endAt);
      await store.updateSchedule(schedule.id, {
        ...scheduleTemplate(values),
        frequency: recurrence.frequency,
        nextOccurrenceAt,
        endAt: recurrence.endAt,
        updatedAt: new Date(),
      });
      const updated = await store.updateTransaction(input.id, values);
      return updated ? schedule.id : undefined;
    }

    const schedule = await store.insertSchedule({
      ...scheduleTemplate(values),
      frequency: recurrence.frequency,
      startAt: values.occurredAt,
      lastOccurrenceAt: values.occurredAt,
      nextOccurrenceAt: boundedNextOccurrence(
        values.occurredAt,
        values.occurredAt,
        recurrence.frequency,
        recurrence.endAt,
      ),
      endAt: recurrence.endAt,
    });
    const updated = await store.updateTransaction(input.id, {
      ...values,
      recurringScheduleId: schedule.id,
    });
    return updated ? schedule.id : undefined;
  });

  if (scheduleId === undefined) {
    return error("transaction_not_found", "Transaction not found");
  }
  if (scheduleId) {
    await materializeRecurringSchedule({ scheduleId }, dependencies);
  }
  const transaction = await dependencies.transactions.findDetailed(input.id);
  if (!transaction) throw new Error("Transaction not found after save");
  return ok(transaction);
}
