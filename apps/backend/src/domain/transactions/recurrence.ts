import type { RecurrenceFrequency } from "./transaction.ts";
import { createCalendar } from "../shared/calendar.ts";

const MAX_OCCURRENCES_PER_MATERIALIZATION = 10_000;

export function nextRecurrenceDate(
  after: Date,
  startAt: Date,
  frequency: RecurrenceFrequency,
  timeZone?: string | null,
): Date {
  if (timeZone) {
    const calendar = createCalendar(startAt.toISOString(), timeZone, true);
    const startLocal = new Date(calendar.localReference() + "Z");
    const afterLocal = new Date(createCalendar(after.toISOString(), timeZone).localReference() + "Z");
    const unit = { daily: "day", weekly: "week", monthly: "month", yearly: "year" } as const;
    const elapsed = frequency === "monthly" ? (afterLocal.getUTCFullYear() - startLocal.getUTCFullYear()) * 12 + afterLocal.getUTCMonth() - startLocal.getUTCMonth()
      : frequency === "yearly" ? afterLocal.getUTCFullYear() - startLocal.getUTCFullYear()
      : Math.floor((afterLocal.getTime() - startLocal.getTime()) / (86_400_000 * (frequency === "weekly" ? 7 : 1)));
    for (let count = Math.max(1, elapsed); count <= 10_000; count++) {
      const candidate = calendar.add(startAt, unit[frequency], count);
      if (candidate > after) return candidate;
    }
    throw new Error("The schedule exceeds the supported range");
  }
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
  timeZone?: string | null,
): { dates: Date[]; nextOccurrenceAt: Date | null } {
  const dates: Date[] = [];
  let cursor = nextOccurrenceAt;

  while (cursor <= through && (!endAt || cursor <= endAt) && dates.length < limit) {
    dates.push(cursor);
    cursor = nextRecurrenceDate(cursor, startAt, frequency, timeZone);
  }

  return {
    dates,
    nextOccurrenceAt: endAt && cursor > endAt ? null : cursor,
  };
}

export function boundedNextOccurrence(
  after: Date,
  startAt: Date,
  frequency: RecurrenceFrequency,
  endAt: Date | null,
  timeZone?: string | null,
): Date | null {
  return boundExistingNext(nextRecurrenceDate(after, startAt, frequency, timeZone), endAt);
}

export function boundExistingNext(next: Date, endAt: Date | null): Date | null {
  return endAt && next > endAt ? null : next;
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
    if (candidate > after) return candidate;
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
    if (candidate > after) return candidate;
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
  return new Date(Date.UTC(
    year,
    month,
    Math.min(requestedDay, lastDay),
    timeSource.getUTCHours(),
    timeSource.getUTCMinutes(),
    timeSource.getUTCSeconds(),
    timeSource.getUTCMilliseconds(),
  ));
}
