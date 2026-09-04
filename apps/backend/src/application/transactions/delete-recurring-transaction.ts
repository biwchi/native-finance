import { nextRecurrenceDate } from "../../domain/transactions/recurrence.ts";
import { error, ok, type Result } from "../../domain/shared/result.ts";
import type { TransactionRepository } from "./transaction.repository.ts";

export type RecurringDeletionAction =
  | "occurrence"
  | "stopRepeating"
  | "occurrenceAndFuture";

type DeleteRecurringError = "recurring_transaction_not_found" | "stale_occurrence";

export async function deleteRecurringTransaction(
  input: {
    scheduleId: string;
    occurredAt: Date;
    action: RecurringDeletionAction;
  },
  dependencies: { transactions: TransactionRepository; now?: () => Date },
): Promise<Result<{ deleted: boolean; stopped: boolean }, DeleteRecurringError>> {
  const now = (dependencies.now ?? (() => new Date()))();
  return dependencies.transactions.atomically(async (store) => {
    const schedule = await store.findSchedule(input.scheduleId, true);
    if (!schedule) {
      return error(
        "recurring_transaction_not_found",
        "This recurring transaction no longer exists. Refresh the list.",
      );
    }
    const recorded = await store.findRecordedOccurrence(schedule.id, input.occurredAt);
    const isNext = schedule.nextOccurrenceAt?.getTime() === input.occurredAt.getTime();
    if (!recorded && !isNext) {
      return error(
        "stale_occurrence",
        "This occurrence has changed or was already deleted. Refresh the list.",
      );
    }

    if (input.action === "occurrence") {
      if (recorded) await store.deleteTransaction(recorded.id);
      if (isNext) {
        const next = nextRecurrenceDate(
          input.occurredAt,
          schedule.startAt,
          schedule.frequency,
        );
        await store.updateSchedule(schedule.id, {
          lastOccurrenceAt: input.occurredAt,
          nextOccurrenceAt: schedule.endAt && next > schedule.endAt ? null : next,
          updatedAt: now,
        });
      }
      return ok({ deleted: true, stopped: false });
    }

    await store.deleteFutureTransactions(
      schedule.id,
      now,
      input.action === "stopRepeating" ? recorded?.id : undefined,
    );
    if (input.action === "occurrenceAndFuture" && recorded) {
      await store.deleteTransaction(recorded.id);
    }
    if (input.action === "stopRepeating" && !recorded) {
      await store.insertTransaction({
        accountId: schedule.accountId,
        kind: schedule.kind,
        amount: schedule.amount,
        currency: schedule.currency,
        categoryId: schedule.categoryId,
        merchant: schedule.merchant,
        payee: schedule.payee,
        note: schedule.note,
        occurredAt: input.occurredAt,
      });
    }
    await store.deleteSchedule(schedule.id);
    return ok({
      deleted: input.action !== "stopRepeating",
      stopped: true,
    });
  });
}
