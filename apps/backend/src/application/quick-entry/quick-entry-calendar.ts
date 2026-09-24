import type { CalendarUnit, ExtractedDate } from "./quick-entry-extraction.ts";

type LocalDate = { year: number; month: number; day: number; hour: number; minute: number; second: number };

export function createQuickEntryCalendar(referenceNow: string, timeZone: string) {
  const reference = new Date(referenceNow);
  if (!Number.isFinite(reference.getTime())) throw new Error("Invalid reference time");
  reference.setUTCMilliseconds(0);
  const formatter = new Intl.DateTimeFormat("en-CA", {
    timeZone, calendar: "gregory", numberingSystem: "latn", hourCycle: "h23",
    year: "numeric", month: "2-digit", day: "2-digit", hour: "2-digit", minute: "2-digit", second: "2-digit",
  });
  const local = (date: Date): LocalDate => {
    const parts = formatter.formatToParts(date);
    const value = (name: Intl.DateTimeFormatPartTypes) => Number(parts.find((part) => part.type === name)?.value);
    return { year: value("year"), month: value("month"), day: value("day"), hour: value("hour"), minute: value("minute"), second: value("second") };
  };
  const instant = (parts: LocalDate): Date => {
    const naive = utcDate(parts).getTime();
    // Sample both sides of a timezone transition. Reject missing or ambiguous
    // wall-clock times instead of silently shifting a financial record.
    const matches = new Set<number>();
    for (const delta of [-36, 0, 36]) {
      const sample = new Date(naive + delta * 3_600_000);
      const offset = utcDate(local(sample)).getTime() - sample.getTime();
      const candidate = naive - offset;
      if (sameLocal(local(new Date(candidate)), parts)) matches.add(candidate);
    }
    if (matches.size !== 1) throw new Error("The date or time needs confirmation in your timezone.");
    return new Date([...matches][0]!);
  };
  const add = (date: Date, unit: CalendarUnit, count: number): Date => instant(shift(local(date), unit, count));

  return {
    reference,
    add,
    localReference: () => {
      const p = local(reference);
      return `${p.year}-${pad(p.month)}-${pad(p.day)}T${pad(p.hour)}:${pad(p.minute)}:${pad(p.second)}`;
    },
    resolve(expression: ExtractedDate | null, base = reference): Date {
      if (!expression) return base;
      const selectors = [expression.calendarDate, expression.relative, expression.weekday].filter(Boolean);
      if (selectors.length > 1) throw new Error("The transaction has conflicting dates.");
      if (selectors.length === 0 && !expression.time) throw new Error("The stated date could not be resolved.");
      let parts = local(base);
      if (expression.calendarDate) {
        parts = { ...parts, ...expression.calendarDate, year: expression.calendarDate.year ?? parts.year };
        if (!sameLocal(fromUTC(utcDate(parts)), parts)) throw new Error("The stated calendar date is invalid.");
      } else if (expression.relative) {
        parts = shift(parts, expression.relative.unit, expression.relative.value);
      } else if (expression.weekday) {
        const today = utcDate(parts).getUTCDay() || 7;
        let days = expression.weekday.day - today;
        if (expression.weekday.relation === "last" && days >= 0) days -= 7;
        if (expression.weekday.relation === "next" && days <= 0) days += 7;
        parts = shift(parts, "day", days);
      }
      if (expression.time) {
        if (!/^(?:[01]\d|2[0-3]):[0-5]\d:[0-5]\d$/.test(expression.time)) throw new Error("The stated time is invalid.");
        const [hour, minute, second] = expression.time.split(":").map(Number);
        parts = { ...parts, hour: hour!, minute: minute!, second: second! };
      }
      return instant(parts);
    },
    countOccurrences(start: Date, boundary: Date, unit: CalendarUnit, inclusive: boolean): number {
      for (let count = 0; count <= 10_000; count++) {
        const occurrence = add(start, unit, count);
        if (inclusive ? occurrence > boundary : occurrence >= boundary) {
          if (count === 0) throw new Error("The schedule ends before its first payment.");
          return count;
        }
      }
      throw new Error("The schedule has too many occurrences to resolve.");
    },
  };
}

function shift(parts: LocalDate, unit: CalendarUnit, count: number): LocalDate {
  if (!Number.isInteger(count) || Math.abs(count) > 10_000) throw new Error("The date offset is invalid.");
  const date = utcDate(parts);
  if (unit === "day" || unit === "week") {
    date.setUTCDate(date.getUTCDate() + count * (unit === "week" ? 7 : 1));
  } else {
    date.setUTCDate(1);
    date.setUTCMonth(date.getUTCMonth() + count * (unit === "year" ? 12 : 1));
    const end = new Date(date);
    end.setUTCMonth(end.getUTCMonth() + 1, 0);
    date.setUTCDate(Math.min(parts.day, end.getUTCDate()));
  }
  const result = fromUTC(date);
  if (result.year < 1900 || result.year > 9999) throw new Error("The date is outside the supported range.");
  return result;
}

function utcDate(parts: LocalDate): Date {
  const date = new Date(0);
  date.setUTCFullYear(parts.year, parts.month - 1, parts.day);
  date.setUTCHours(parts.hour, parts.minute, parts.second, 0);
  return date;
}

function fromUTC(date: Date): LocalDate {
  return { year: date.getUTCFullYear(), month: date.getUTCMonth() + 1, day: date.getUTCDate(), hour: date.getUTCHours(), minute: date.getUTCMinutes(), second: date.getUTCSeconds() };
}

function sameLocal(a: LocalDate, b: LocalDate) { return Object.keys(a).every((key) => a[key as keyof LocalDate] === b[key as keyof LocalDate]); }
function pad(value: number) { return String(value).padStart(2, "0"); }
