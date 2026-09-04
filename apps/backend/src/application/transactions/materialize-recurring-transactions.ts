import { materializeRecurringSchedule } from "./materialize-recurring-schedule.ts";
import type { TransactionRepository } from "./transaction.repository.ts";

export async function materializeRecurringTransactions(
  input: { through?: Date },
  dependencies: { transactions: TransactionRepository },
): Promise<void> {
  const through = input.through ?? new Date();
  const schedules = await dependencies.transactions.findDueSchedules(through);
  for (const schedule of schedules) {
    await materializeRecurringSchedule(
      { scheduleId: schedule.id, through },
      dependencies,
    );
  }
}
