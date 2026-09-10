import type { SyncChange } from "../../application/sync/sync.repository.ts";

const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
export function identifier(value: unknown): string {
  if (typeof value !== "string" || !uuidPattern.test(value)) throw new Error("Invalid record identifier");
  return value.toLowerCase();
}
export function optionalId(value: unknown): string | null { return value == null ? null : identifier(value); }
export function text(value: unknown, max: number, optional = false): string | null {
  if (value == null && optional) return null;
  if (typeof value !== "string" || value.length > max || (!optional && !value.trim())) throw new Error("Invalid text value");
  return value.trim() || null;
}
export function money(value: unknown, optional = false): string | null {
  if (value == null && optional) return null;
  if (typeof value !== "string" || !/^(?!0+(?:\.0{1,4})?$)(?:0|[1-9]\d{0,14})(?:\.\d{1,4})?$/.test(value)) throw new Error("Enter a positive amount with at most four decimal places");
  return value;
}
export function date(value: unknown, optional = false): string | null {
  if (value == null && optional) return null;
  if (typeof value !== "string" || !Number.isFinite(Date.parse(value))) throw new Error("Invalid date");
  return new Date(value).toISOString();
}
export function choice<T extends string>(value: unknown, choices: readonly T[]): T {
  if (typeof value !== "string" || !choices.includes(value as T)) throw new Error("Invalid selection");
  return value as T;
}
export function currency(value: unknown): string {
  if (typeof value !== "string" || !/^[A-Za-z]{3}$/.test(value)) throw new Error("Invalid currency");
  return value.toUpperCase();
}
export function sortOrder(value: unknown): number {
  if (typeof value !== "number" || !Number.isSafeInteger(value) || value < 0 || value > 2147483647) throw new Error("Invalid sort order");
  return value;
}
export const colors = ["red", "coral", "orange", "amber", "yellow", "lime", "green", "mint", "teal", "turquoise", "cyan", "sky", "blue", "navy", "indigo", "violet", "purple", "lavender", "pink", "rose", "brown", "slate", "gray"] as const;

export function normalizeChange(change: SyncChange): SyncChange {
  if (change.entity !== "budget") change.key = identifier(change.key);
  if (change.entity === "budget" && change.key !== "all") change.key = identifier(change.key);
  if (!change.data) return change;
  const d = change.data;
  const id = identifier(d.id);
  if (change.entity !== "budget" && id !== change.key) throw new Error("Record ID does not match its key");
  const times = change.entity === "debt" || change.entity === "exclusion" ? {} : { createdAt: date(d.createdAt), updatedAt: date(d.updatedAt) };
  let data: Record<string, unknown>;
  switch (change.entity) {
    case "account":
      data = { id, ...times, name: text(d.name, 120), type: choice(d.type, ["cash", "checking", "savings", "credit", "investment"]), currency: currency(d.currency), icon: text(d.icon, 80), iconColor: choice(d.iconColor, ["blue", "indigo", "purple", "pink", "red", "orange", "green", "teal", "gray"]), sortOrder: sortOrder(d.sortOrder) }; break;
    case "category":
      data = { id, ...times, name: text(d.name, 80), kind: choice(d.kind, ["expense", "income"]), parentId: optionalId(d.parentId), icon: text(d.icon, 80, true), color: d.color == null ? null : choice(d.color, colors), sortOrder: sortOrder(d.sortOrder ?? 1000) }; break;
    case "debt":
      data = { id, name: text(d.name, 200), icon: text(d.icon ?? "user", 80), color: choice(d.color ?? "blue", colors) }; break;
    case "transaction":
    case "schedule": {
      data = { id, ...times, accountId: identifier(d.accountId), kind: choice(d.kind, ["expense", "income", "debt"]), amount: money(d.amount), currency: currency(d.currency), categoryId: optionalId(d.categoryId), merchant: text(d.merchant, 500, true), payee: text(d.payee, 500, true), note: text(d.note, 2000, true) };
      if (change.entity === "transaction") Object.assign(data, { debtId: optionalId(d.debtId), recurringScheduleId: optionalId(d.recurringScheduleId), occurredAt: date(d.occurredAt), scheduledFor: date(d.scheduledFor, true) });
      else Object.assign(data, { frequency: choice(d.frequency, ["daily", "weekly", "monthly", "yearly"]), startAt: date(d.startAt), lastOccurrenceAt: date(d.lastOccurrenceAt), nextScheduledFor: date(d.nextScheduledFor, true), nextOccurrenceAt: date(d.nextOccurrenceAt, true), endAt: date(d.endAt, true) });
      break;
    }
    case "exclusion": data = { id, scheduleId: identifier(d.scheduleId), scheduledFor: date(d.scheduledFor) }; break;
    case "budget": {
      if (!Array.isArray(d.groups) || !Array.isArray(d.categoryAssignments) || d.groups.length > 100 || d.categoryAssignments.length > 500) throw new Error("Invalid budget");
      data = { id, ...times, accountId: optionalId(d.accountId), currency: currency(d.currency), monthlyLimit: money(d.monthlyLimit, true), groups: d.groups.map((g, index) => ({ id: identifier(g.id), name: text(g.name, 80), limit: money(g.limit), sortOrder: index })), categoryAssignments: d.categoryAssignments.map((a) => ({ categoryId: identifier(a.categoryId), groupId: optionalId(a.groupId), limit: money(a.limit, true) })) };
      if (change.key !== (data.accountId ?? "all")) throw new Error("Budget scope does not match its key");
      break;
    }
  }
  return { ...change, data };
}
