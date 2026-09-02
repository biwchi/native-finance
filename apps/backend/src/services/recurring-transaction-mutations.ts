import { and, asc, eq, gt, ne, or } from "drizzle-orm";

import { db } from "../db/client.ts";
import { recurringSchedules, transactions } from "../db/schema.ts";
import { nextRecurrenceDate, type RecurrenceFrequency } from "./recurring-transactions.ts";

export type RecurringDeletionAction = "occurrence" | "stopRepeating" | "occurrenceAndFuture";

export class RecurringMutationError extends Error {
  constructor(message: string, readonly status: 404 | 409) { super(message); }
}

type TemplateValues = Pick<typeof transactions.$inferSelect,
  "accountId" | "kind" | "amount" | "currency" | "categoryId" | "merchant" | "payee" | "note" | "occurredAt"
>;

export async function updateRecurringTemplate(
  scheduleId: string,
  expectedOccurredAt: Date,
  values: TemplateValues,
  recurrence: { frequency: RecurrenceFrequency; endAt: Date | null } | null,
  now = new Date(),
): Promise<void> {
  await db.transaction(async (transaction) => {
    const [schedule] = await transaction.select().from(recurringSchedules)
      .where(eq(recurringSchedules.id, scheduleId)).for("update");
    if (!schedule) throw new RecurringMutationError("This recurring transaction no longer exists. Refresh the list.", 404);

    const [firstRecorded] = await transaction.select().from(transactions)
      .where(and(eq(transactions.recurringScheduleId, scheduleId), gt(transactions.occurredAt, now)))
      .orderBy(asc(transactions.occurredAt)).limit(1);
    const nextDate = [schedule.nextOccurrenceAt, firstRecorded?.occurredAt]
      .filter((date): date is Date => date != null && (!schedule.endAt || date <= schedule.endAt))
      .sort((a, b) => a.getTime() - b.getTime())[0];
    if (!nextDate || nextDate <= now || nextDate.getTime() !== expectedOccurredAt.getTime() || values.occurredAt <= now) {
      throw new RecurringMutationError("The next occurrence has changed or is already due. Refresh the list before editing it.", 409);
    }
    const recorded = firstRecorded?.occurredAt.getTime() === nextDate.getTime() ? firstRecorded : undefined;

    // Only the selected upcoming occurrence is retained; past ledger entries are never rewritten.
    await transaction.delete(transactions).where(and(
      eq(transactions.recurringScheduleId, scheduleId),
      gt(transactions.occurredAt, now),
      recorded ? ne(transactions.id, recorded.id) : undefined,
    ));
    if (recorded) {
      await transaction.update(transactions).set({ ...values, updatedAt: now })
        .where(eq(transactions.id, recorded.id));
    } else if (!recurrence) {
      await transaction.insert(transactions).values(values);
    }

    if (!recurrence) {
      await transaction.delete(recurringSchedules).where(eq(recurringSchedules.id, scheduleId));
      return;
    }

    const dateChanged = values.occurredAt.getTime() !== expectedOccurredAt.getTime();
    const startAt = dateChanged || recurrence.frequency !== schedule.frequency ? values.occurredAt : schedule.startAt;
    const nextOccurrenceAt = recorded
      ? nextRecurrenceDate(values.occurredAt, startAt, recurrence.frequency)
      : values.occurredAt;
    const { occurredAt, ...template } = values;
    await transaction.update(recurringSchedules).set({
      ...template,
      ...recurrence,
      startAt,
      lastOccurrenceAt: recorded ? occurredAt : schedule.lastOccurrenceAt,
      nextOccurrenceAt: recurrence.endAt && nextOccurrenceAt > recurrence.endAt ? null : nextOccurrenceAt,
      updatedAt: now,
    }).where(eq(recurringSchedules.id, scheduleId));
  });
}

export async function deleteRecurringOccurrence(
  scheduleId: string,
  occurredAt: Date,
  action: RecurringDeletionAction,
  now = new Date(),
): Promise<void> {
  await db.transaction(async (transaction) => {
    const [schedule] = await transaction.select().from(recurringSchedules)
      .where(eq(recurringSchedules.id, scheduleId)).for("update");
    if (!schedule) throw new RecurringMutationError("This recurring transaction no longer exists. Refresh the list.", 404);

    const [recorded] = await transaction.select().from(transactions).where(and(
      eq(transactions.recurringScheduleId, scheduleId), eq(transactions.occurredAt, occurredAt),
    )).limit(1);
    const isNext = schedule.nextOccurrenceAt?.getTime() === occurredAt.getTime();
    if (!recorded && !isNext) {
      throw new RecurringMutationError("This occurrence has changed or was already deleted. Refresh the list.", 409);
    }

    if (action === "occurrence") {
      if (recorded) await transaction.delete(transactions).where(eq(transactions.id, recorded.id));
      if (isNext) {
        const next = nextRecurrenceDate(occurredAt, schedule.startAt, schedule.frequency);
        await transaction.update(recurringSchedules).set({
          lastOccurrenceAt: occurredAt,
          nextOccurrenceAt: schedule.endAt && next > schedule.endAt ? null : next,
          updatedAt: now,
        }).where(eq(recurringSchedules.id, scheduleId));
      }
      return;
    }

    await transaction.delete(transactions).where(and(
      eq(transactions.recurringScheduleId, scheduleId),
      action === "stopRepeating"
        ? and(gt(transactions.occurredAt, now), recorded ? ne(transactions.id, recorded.id) : undefined)
        : or(gt(transactions.occurredAt, now), recorded ? eq(transactions.id, recorded.id) : undefined),
    ));
    if (action === "stopRepeating" && !recorded) {
      // Preserve the chosen occurrence as a one-time entry without scheduling later repeats.
      await transaction.insert(transactions).values({
        accountId: schedule.accountId, kind: schedule.kind, amount: schedule.amount,
        currency: schedule.currency, categoryId: schedule.categoryId,
        merchant: schedule.merchant, payee: schedule.payee, note: schedule.note, occurredAt,
      });
    }
    await transaction.delete(recurringSchedules).where(eq(recurringSchedules.id, scheduleId));
  });
}
