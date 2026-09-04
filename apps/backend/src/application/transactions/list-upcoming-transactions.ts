import type { UpcomingTransaction } from "../../domain/transactions/transaction.ts";
import { materializeRecurringTransactions } from "./materialize-recurring-transactions.ts";
import type { TransactionRepository } from "./transaction.repository.ts";

export async function listUpcomingTransactions(
  input: { accountId?: string },
  dependencies: { transactions: TransactionRepository; now?: () => Date },
): Promise<UpcomingTransaction[]> {
  const now = (dependencies.now ?? (() => new Date()))();
  await materializeRecurringTransactions({ through: now }, dependencies);

  const [schedules, recorded] = await Promise.all([
    dependencies.transactions.listSchedules(input.accountId),
    dependencies.transactions.listRecordedFuture(input.accountId, now),
  ]);
  const firstRecorded = new Map<string, Date>();
  for (const occurrence of recorded) {
    if (!firstRecorded.has(occurrence.scheduleId)) {
      firstRecorded.set(occurrence.scheduleId, occurrence.occurredAt);
    }
  }

  return schedules.flatMap((schedule) => {
    const occurredAt = [schedule.nextOccurrenceAt, firstRecorded.get(schedule.id)]
      .filter((date): date is Date =>
        date !== null && date !== undefined && date > now &&
        (!schedule.endAt || date <= schedule.endAt)
      )
      .sort((left, right) => left.getTime() - right.getTime())[0];
    if (!occurredAt) return [];
    return [{
      id: schedule.id,
      accountId: schedule.accountId,
      kind: schedule.kind,
      amount: schedule.amount,
      currency: schedule.currency,
      category: schedule.category,
      merchant: schedule.merchant,
      payee: schedule.payee,
      note: schedule.note,
      frequency: schedule.frequency,
      startAt: schedule.startAt,
      endAt: schedule.endAt,
      occurredAt,
    }];
  }).sort((left, right) =>
    left.occurredAt.getTime() - right.occurredAt.getTime() ||
    left.id.localeCompare(right.id)
  );
}
