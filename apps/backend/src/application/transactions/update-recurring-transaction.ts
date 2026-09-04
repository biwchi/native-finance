import { nextRecurrenceDate } from "../../domain/transactions/recurrence.ts";
import type {
  TransactionInput,
  TransactionValidationError,
} from "../../domain/transactions/transaction.ts";
import { error, ok, type Result } from "../../domain/shared/result.ts";
import type { AccountRepository } from "../accounts/account.repository.ts";
import type { CategoryRepository } from "../categories/category.repository.ts";
import { prepareTransaction } from "./prepare-transaction.ts";
import { scheduleTemplate } from "./recurring-values.ts";
import type { TransactionRepository } from "./transaction.repository.ts";

type UpdateRecurringError =
  | TransactionValidationError
  | "recurring_transaction_not_found"
  | "stale_occurrence";

export async function updateRecurringTransaction(
  input: {
    scheduleId: string;
    expectedOccurredAt: string;
    transaction: TransactionInput;
  },
  dependencies: {
    accounts: AccountRepository;
    categories: CategoryRepository;
    transactions: TransactionRepository;
    now?: () => Date;
  },
): Promise<Result<{ updated: true }, UpdateRecurringError>> {
  const prepared = await prepareTransaction(input.transaction, dependencies);
  if (!prepared.ok) return prepared;
  const { values, recurrence } = prepared.value;
  const expectedOccurredAt = new Date(input.expectedOccurredAt);
  const now = (dependencies.now ?? (() => new Date()))();

  return dependencies.transactions.atomically(async (store) => {
    const schedule = await store.findSchedule(input.scheduleId, true);
    if (!schedule) {
      return error(
        "recurring_transaction_not_found",
        "This recurring transaction no longer exists. Refresh the list.",
      );
    }

    const firstRecorded = await store.findFirstRecordedFuture(schedule.id, now);
    const nextDate = [schedule.nextOccurrenceAt, firstRecorded?.occurredAt]
      .filter((date): date is Date =>
        date !== null && date !== undefined && (!schedule.endAt || date <= schedule.endAt)
      )
      .sort((left, right) => left.getTime() - right.getTime())[0];
    if (
      !nextDate ||
      nextDate <= now ||
      nextDate.getTime() !== expectedOccurredAt.getTime() ||
      values.occurredAt <= now
    ) {
      return error(
        "stale_occurrence",
        "The next occurrence has changed or is already due. Refresh the list before editing it.",
      );
    }
    const recorded = firstRecorded?.occurredAt.getTime() === nextDate.getTime()
      ? firstRecorded
      : null;

    await store.deleteFutureTransactions(schedule.id, now, recorded?.id);
    if (recorded) {
      await store.updateTransaction(recorded.id, {
        ...values,
        updatedAt: now,
      });
    } else if (!recurrence) {
      await store.insertTransaction(values);
    }

    if (!recurrence) {
      await store.deleteSchedule(schedule.id);
      return ok({ updated: true as const });
    }

    const dateChanged =
      values.occurredAt.getTime() !== expectedOccurredAt.getTime();
    const startAt = dateChanged || recurrence.frequency !== schedule.frequency
      ? values.occurredAt
      : schedule.startAt;
    const nextOccurrenceAt = recorded
      ? nextRecurrenceDate(
          values.occurredAt,
          startAt,
          recurrence.frequency,
        )
      : values.occurredAt;
    await store.updateSchedule(schedule.id, {
      ...scheduleTemplate(values),
      ...recurrence,
      startAt,
      lastOccurrenceAt: recorded
        ? values.occurredAt
        : schedule.lastOccurrenceAt,
      nextOccurrenceAt: recurrence.endAt && nextOccurrenceAt > recurrence.endAt
        ? null
        : nextOccurrenceAt,
      updatedAt: now,
    });
    return ok({ updated: true as const });
  });
}
