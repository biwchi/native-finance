import { recurrencePlan } from "../../domain/transactions/recurrence.ts";
import type { TransactionRepository } from "./transaction.repository.ts";

export async function materializeRecurringSchedule(
  input: { scheduleId: string; through?: Date },
  dependencies: { transactions: TransactionRepository },
): Promise<void> {
  const through = input.through ?? new Date();
  await dependencies.transactions.atomically(async (store) => {
    const schedule = await store.findSchedule(input.scheduleId, true);
    if (!schedule?.nextOccurrenceAt) return;

    const plan = recurrencePlan(
      schedule.nextOccurrenceAt,
      schedule.startAt,
      schedule.frequency,
      schedule.endAt,
      through,
    );
    await store.insertOccurrences(schedule, plan.dates);
    await store.updateSchedule(schedule.id, {
      lastOccurrenceAt: plan.dates.at(-1) ?? schedule.lastOccurrenceAt,
      nextOccurrenceAt: plan.nextOccurrenceAt,
      updatedAt: new Date(),
    });
  });
}
