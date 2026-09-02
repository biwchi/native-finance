import { and, eq, isNotNull, lte } from "drizzle-orm";

import { db } from "../db/client.ts";
import {
  recurringSchedules,
  transactions,
  type RecurringSchedule,
} from "../db/schema.ts";

export type RecurrenceFrequency =
  | "daily"
  | "weekly"
  | "monthly"
  | "yearly";

const MAX_OCCURRENCES_PER_MATERIALIZATION = 10_000;

export function nextRecurrenceDate(
  after: Date,
  startAt: Date,
  frequency: RecurrenceFrequency,
): Date {
  switch (frequency) {
    case "daily":
      return addingUTCDays(after, 1);
    case "weekly":
      return addingUTCDays(after, 7);
    case "monthly":
      return nextMonthlyDate(after, startAt);
    case "yearly":
      return nextYearlyDate(after, startAt);
  }
}

export function recurrencePlan(
  nextOccurrenceAt: Date,
  startAt: Date,
  frequency: RecurrenceFrequency,
  endAt: Date | null,
  through: Date,
  limit = MAX_OCCURRENCES_PER_MATERIALIZATION,
): { dates: Date[]; nextOccurrenceAt: Date | null } {
  const dates: Date[] = [];
  let cursor = nextOccurrenceAt;

  while (
    cursor <= through &&
    (!endAt || cursor <= endAt) &&
    dates.length < limit
  ) {
    dates.push(cursor);
    cursor = nextRecurrenceDate(cursor, startAt, frequency);
  }

  return {
    dates,
    nextOccurrenceAt: endAt && cursor > endAt ? null : cursor,
  };
}

export async function materializeRecurringTransactions(
  through = new Date(),
): Promise<void> {
  const dueSchedules = await db
    .select()
    .from(recurringSchedules)
    .where(
      and(
        isNotNull(recurringSchedules.nextOccurrenceAt),
        lte(recurringSchedules.nextOccurrenceAt, through),
      ),
    );

  for (const schedule of dueSchedules) {
    await materializeSchedule(schedule, through);
  }
}

export async function materializeRecurringSchedule(
  scheduleId: string,
  through = new Date(),
): Promise<void> {
  const [schedule] = await db
    .select()
    .from(recurringSchedules)
    .where(eq(recurringSchedules.id, scheduleId))
    .limit(1);

  if (schedule) {
    await materializeSchedule(schedule, through);
  }
}

async function materializeSchedule(
  schedule: RecurringSchedule,
  through: Date,
): Promise<void> {
  if (!schedule.nextOccurrenceAt) {
    return;
  }

  const plan = recurrencePlan(
    schedule.nextOccurrenceAt,
    schedule.startAt,
    schedule.frequency,
    schedule.endAt,
    through,
  );

  await db.transaction(async (transaction) => {
    if (plan.dates.length > 0) {
      await transaction
        .insert(transactions)
        .values(
          plan.dates.map((occurredAt) => ({
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
          })),
        )
        .onConflictDoNothing();
    }

    await transaction
      .update(recurringSchedules)
      .set({
        lastOccurrenceAt:
          plan.dates[plan.dates.length - 1] ?? schedule.lastOccurrenceAt,
        nextOccurrenceAt: plan.nextOccurrenceAt,
        updatedAt: new Date(),
      })
      .where(eq(recurringSchedules.id, schedule.id));
  });
}

function addingUTCDays(date: Date, days: number): Date {
  const result = new Date(date);
  result.setUTCDate(result.getUTCDate() + days);
  return result;
}

function nextMonthlyDate(after: Date, startAt: Date): Date {
  let monthIndex = after.getUTCFullYear() * 12 + after.getUTCMonth() + 1;

  while (true) {
    const year = Math.floor(monthIndex / 12);
    const month = monthIndex % 12;
    const candidate = anchoredUTCDate(year, month, startAt.getUTCDate(), startAt);
    if (candidate > after) {
      return candidate;
    }
    monthIndex += 1;
  }
}

function nextYearlyDate(after: Date, startAt: Date): Date {
  let year = after.getUTCFullYear() + 1;

  while (true) {
    const candidate = anchoredUTCDate(
      year,
      startAt.getUTCMonth(),
      startAt.getUTCDate(),
      startAt,
    );
    if (candidate > after) {
      return candidate;
    }
    year += 1;
  }
}

function anchoredUTCDate(
  year: number,
  month: number,
  requestedDay: number,
  timeSource: Date,
): Date {
  const lastDay = new Date(Date.UTC(year, month + 1, 0)).getUTCDate();
  return new Date(
    Date.UTC(
      year,
      month,
      Math.min(requestedDay, lastDay),
      timeSource.getUTCHours(),
      timeSource.getUTCMinutes(),
      timeSource.getUTCSeconds(),
      timeSource.getUTCMilliseconds(),
    ),
  );
}
