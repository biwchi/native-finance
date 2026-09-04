import { boundedNextOccurrence } from "../../domain/transactions/recurrence.ts";
import type {
  TransactionInput,
  TransactionValidationError,
} from "../../domain/transactions/transaction.ts";
import { ok, type Result } from "../../domain/shared/result.ts";
import type { AccountRepository } from "../accounts/account.repository.ts";
import type { CategoryRepository } from "../categories/category.repository.ts";
import { prepareTransaction } from "./prepare-transaction.ts";
import { materializeRecurringSchedule } from "./materialize-recurring-schedule.ts";
import { scheduleTemplate } from "./recurring-values.ts";
import type { TransactionRepository } from "./transaction.repository.ts";

export async function createTransaction(
  input: TransactionInput,
  dependencies: {
    accounts: AccountRepository;
    categories: CategoryRepository;
    transactions: TransactionRepository;
  },
): Promise<Result<
  NonNullable<Awaited<ReturnType<TransactionRepository["findDetailed"]>>>,
  TransactionValidationError
>> {
  const prepared = await prepareTransaction(input, dependencies);
  if (!prepared.ok) return prepared;
  const { values, recurrence } = prepared.value;

  const created = await dependencies.transactions.atomically(async (store) => {
    if (!recurrence) {
      const transaction = await store.insertTransaction(values);
      return { transactionId: transaction.id, scheduleId: null };
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
    const transaction = await store.insertTransaction({
      ...values,
      recurringScheduleId: schedule.id,
    });
    return { transactionId: transaction.id, scheduleId: schedule.id };
  });

  if (created.scheduleId) {
    await materializeRecurringSchedule(
      { scheduleId: created.scheduleId },
      dependencies,
    );
  }
  const transaction = await dependencies.transactions.findDetailed(created.transactionId);
  if (!transaction) throw new Error("Transaction not found after save");
  return ok(transaction);
}
