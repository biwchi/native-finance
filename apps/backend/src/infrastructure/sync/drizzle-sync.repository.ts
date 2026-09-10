import { occurrenceId } from "../../domain/transactions/occurrence-id.ts";
import { createHash } from "node:crypto";
import { and, asc, eq, gt, inArray, lte, sql } from "drizzle-orm";
import type { Database } from "../db/client.ts";
import { syncChanges, syncReceipts, syncRecords, syncWorkspace } from "../db/schema/sync.schema.ts";
import type { SyncChange, SyncEntity, SyncMutation, SyncRecord, SyncRepository, SyncResult } from "../../application/sync/sync.repository.ts";
import { createBudget, type BudgetInput } from "../../domain/budgets/budget.ts";
import type { Account } from "../../domain/accounts/account.ts";
import type { Category } from "../../domain/categories/category.ts";
import { normalizeChange } from "./sync-validation.ts";

const tables: Record<Exclude<SyncEntity, "budget">, string> = { account: "accounts", category: "categories", debt: "debts", transaction: "transactions", schedule: "recurring_schedules", exclusion: "recurrence_exclusions" };
const order: Record<SyncEntity, number> = { account: 0, category: 1, debt: 2, schedule: 3, transaction: 4, exclusion: 5, budget: 6 };
const wire = (row: typeof syncRecords.$inferSelect): SyncRecord => ({ entity: row.entity as SyncEntity, key: row.key, version: row.version.toString(), data: row.data });
const snake = (value: string) => value.replace(/[A-Z]/g, (letter) => `_${letter.toLowerCase()}`);

export function createDrizzleSyncRepository(database: Database): SyncRepository {
  async function workspace(client: Database) {
    const [row] = await client.select().from(syncWorkspace).where(eq(syncWorkspace.id, 1));
    if (!row) throw new Error("Apply the local-first database migration before using sync");
    return { workspaceId: row.workspaceId, generation: row.generation, cursor: row.revision.toString() };
  }
  return {
    bootstrap: () => database.transaction(async (tx) => {
      const client = tx as unknown as Database;
      await client.execute(sql`select id from sync_workspace where id = 1 for share`);
      return { ...await workspace(client), records: (await client.select().from(syncRecords)).map(wire) };
    }),
    changes: (cursor, generation) => database.transaction(async (tx) => {
      const client = tx as unknown as Database;
      await client.execute(sql`select id from sync_workspace where id = 1 for share`);
      const state = await workspace(client);
      if (generation !== state.generation) return { ...state, records: [], hasMore: false, reset: true };
      if (BigInt(cursor) > BigInt(state.cursor)) throw new Error("Sync cursor is ahead of this workspace");
      // Page whole commits; never advance past part of a cascading mutation.
      const revisions = await client.selectDistinct({ revision: syncChanges.revision }).from(syncChanges).where(gt(syncChanges.revision, BigInt(cursor))).orderBy(asc(syncChanges.revision)).limit(101);
      const upper = revisions.slice(0, 100).at(-1)?.revision;
      const rows = upper === undefined ? [] : await client.select().from(syncChanges).where(and(gt(syncChanges.revision, BigInt(cursor)), lte(syncChanges.revision, upper))).orderBy(asc(syncChanges.revision));
      return { ...state, cursor: upper?.toString() ?? state.cursor, records: rows.map(wire), hasMore: revisions.length > 100, reset: false };
    }),
    push: (mutation) => database.transaction(async (tx) => {
      const client = tx as unknown as Database;
      await client.execute(sql`select id from sync_workspace where id = 1 for update`);
      const state = await workspace(client);
      const digest = createHash("sha256").update(stableJSON(mutation)).digest("hex");
      const [receipt] = await client.select().from(syncReceipts).where(and(eq(syncReceipts.clientId, mutation.clientId), eq(syncReceipts.mutationId, mutation.mutationId)));
      if (receipt) {
        if (receipt.digest !== digest) return { mutationId: mutation.mutationId, status: "rejected", generation: state.generation, records: [], message: "A mutation ID cannot be reused for different changes" };
        return receipt.response as SyncResult;
      }
      let result: SyncResult;
      try {
        result = await tx.transaction(async (savepoint) => {
          const writer = savepoint as unknown as Database;
          if (mutation.workspaceId && mutation.workspaceId.toLowerCase() !== state.workspaceId) throw new Error("This server belongs to a different workspace");
          if (mutation.generation !== state.generation) return { mutationId: mutation.mutationId, status: "conflict" as const, generation: state.generation, records: [], message: "This workspace was reset. Review your local changes before continuing." };
          const changes = mutation.changes.map((change) => normalizeChange({ ...change }));
          if (new Set(changes.map((c) => `${c.entity}:${c.key}`)).size !== changes.length) throw new Error("A mutation contains duplicate record keys");
          const current = await Promise.all(changes.map((change) => record(writer, change.entity, change.key)));
          const actions = mutation.recurrenceActions ?? [];
          for (const action of actions) {
            if (!changes.some((c) => c.entity === "schedule" && c.key === action.scheduleId.toLowerCase()) && action.action !== "occurrence") throw new Error("A recurrence action requires its schedule mutation");
          }
          const ignored = new Set<string>();
          for (const change of changes) {
            if (change.origin !== "generated") continue;
            if (change.entity !== "transaction" || !change.data?.recurringScheduleId || !change.data.scheduledFor || change.key !== occurrenceId(String(change.data.recurringScheduleId), new Date(String(change.data.scheduledFor)))) throw new Error("Invalid generated occurrence");
            const exclusion = await record(writer, "exclusion", change.key);
            const existing = current[changes.indexOf(change)];
            if (exclusion?.data || existing && !existing.data && change.baseVersion !== existing.version.toString()) ignored.add(change.key);
          }
          const conflicts = changes.filter((change, index) => {
            const existing = current[index];
            if (ignored.has(change.key)) return false;
            if ((existing?.version.toString() ?? null) === change.baseVersion) return false;
            if (change.baseVersion === null && existing?.data && existing.data.createdAt === existing.data.updatedAt && actions.some((a) => a.retainedTransactionId?.toLowerCase() === change.key && existing.data?.recurringScheduleId === a.scheduleId.toLowerCase())) return false;
            // Independent generators can create the same occurrence. A tombstone never matches a create.
            return !(change.baseVersion === null && existing?.data && (change.entity === "exclusion" || change.entity === "transaction" && change.data?.scheduledFor) && comparable(existing.data) === comparable(change.data));
          });
          if (conflicts.length) return { mutationId: mutation.mutationId, status: "conflict" as const, generation: state.generation, records: current.filter((r) => r !== undefined).map(wire), message: "These records changed on another device. Both versions are preserved." };
          const revision = await writer.execute<{ revision: string }>(sql`select finance_sync_lock()::text as revision`);
          if (mutation.reset) {
            if (changes.length) throw new Error("Reset must be a separate mutation");
            await writer.execute(sql`delete from accounts`);
            await writer.execute(sql`delete from budget_plans`);
            await writer.execute(sql`delete from debts`);
            await writer.execute(sql`delete from categories`);
            await writer.execute(sql`delete from recurrence_exclusions`);
            await writer.execute(sql`update sync_workspace set generation = generation + 1 where id = 1`);
          } else {
            // Parent-first writes, then child-first deletions. Every effect is journaled by DB triggers.
            // Apply the user's original boundary even if server generation passed it while offline.
            for (const action of actions) {
              if (action.action === "occurrence") continue;
              const scheduleId = action.scheduleId.toLowerCase();
              await writer.execute(sql`delete from transactions where recurring_schedule_id = ${scheduleId}::uuid and occurred_at > ${action.effectiveAt ?? mutation.authoredAt}::timestamptz and (${action.retainedTransactionId ?? null}::uuid is null or id <> ${action.retainedTransactionId ?? null}::uuid)`);
              if (action.action === "occurrenceAndFuture") await writer.execute(sql`delete from transactions where recurring_schedule_id = ${scheduleId}::uuid and scheduled_for = ${action.targetScheduledFor}::timestamptz`);
            }
            const upserts = changes.filter((c) => c.data && !ignored.has(c.key)).sort((a, b) => order[a.entity] - order[b.entity] || Number(Boolean(a.data?.parentId)) - Number(Boolean(b.data?.parentId)));
            for (const change of upserts) await applyChange(writer, change);
            for (const change of changes.filter((c) => !c.data).sort((a, b) => order[b.entity] - order[a.entity])) await applyChange(writer, change);
          }
          const records = (await writer.select().from(syncChanges).where(eq(syncChanges.revision, BigInt(revision[0]!.revision)))).map(wire);
          // ACK unchanged occurrences too, so dependents receive their existing server version.
          for (const change of changes) {
            if (records.some((r) => r.entity === change.entity && r.key === change.key)) continue;
            const saved = await record(writer, change.entity, change.key);
            if (saved) records.push(wire(saved));
            else if (ignored.has(change.key)) records.push({ entity: change.entity, key: change.key, version: revision[0]!.revision, data: null });
          }
          return { mutationId: mutation.mutationId, status: "accepted" as const, generation: (await workspace(writer)).generation, records };
        });
      } catch (cause) {
        // Transient infrastructure errors must remain retryable, without a permanent receipt.
        const pg = cause as { code?: string; cause?: { code?: string } };
        const code = pg.code ?? pg.cause?.code;
        if (code && !["23505", "23503", "23514", "23502", "22003", "22007", "22P02"].includes(code)) throw cause;
        if (!code && (cause as Error).message?.startsWith("Failed query:")) throw cause;
        result = { mutationId: mutation.mutationId, status: "rejected", generation: state.generation, records: [], message: failureMessage(cause) };
      }
      await client.insert(syncReceipts).values({ clientId: mutation.clientId, mutationId: mutation.mutationId, digest, response: result });
      return result;
    }),
  };
}

async function record(client: Database, entity: string, key: string) {
  const [row] = await client.select().from(syncRecords).where(and(eq(syncRecords.entity, entity), eq(syncRecords.key, key)));
  return row;
}
async function reference(client: Database, entity: SyncEntity, key: unknown) {
  if (key == null) return null;
  const row = await record(client, entity, String(key));
  if (!row?.data) throw new Error(`The referenced ${entity} no longer exists`);
  return row.data;
}
async function applyChange(client: Database, change: SyncChange) {
  const existing = (await record(client, change.entity, change.key))?.data;
  const d = change.data;
  if (!d) {
    if (change.entity === "category" && existing?.isSystem) throw new Error("Built-in categories cannot be deleted");
    if (change.entity === "budget") {
      if (existing) await client.execute(sql`delete from budget_plans where id = ${existing.id}::uuid`);
    } else await client.execute(sql`delete from ${sql.identifier(tables[change.entity])} where id = ${change.key}::uuid`);
    return;
  }
  if (change.entity === "category") {
    if (d.parentId === d.id) throw new Error("A category cannot be its own parent");
    const parent = await reference(client, "category", d.parentId);
    if (parent && (parent.parentId || parent.kind !== d.kind)) throw new Error("Invalid parent category");
    if (existing && existing.kind !== d.kind) throw new Error("Category type cannot change");
    if (d.parentId) {
      const children = await client.execute(sql`select id from categories where parent_id = ${d.id}::uuid limit 1`);
      if (children.length) throw new Error("Move this category's children first");
    }
    Object.assign(d, { isSystem: existing?.isSystem ?? false, systemKey: existing?.systemKey ?? null, examples: existing?.examples ?? [] });
  }
  if (["transaction", "schedule", "budget"].includes(change.entity)) {
    const account = await reference(client, "account", d.accountId);
    if (account && (!existing || existing.accountId !== d.accountId || change.entity === "budget") && d.currency !== account.currency) throw new Error("Currency must match the account");
  }
  if (change.entity === "transaction" || change.entity === "schedule") {
    const category = await reference(client, "category", d.categoryId);
    if (category && category.kind !== d.kind) throw new Error("Category type must match the transaction");
    if (d.kind === "debt") {
      if (change.entity === "schedule" || !d.debtId || d.categoryId || d.recurringScheduleId) throw new Error("Invalid debt transaction");
      await reference(client, "debt", d.debtId);
    } else if (d.debtId) throw new Error("Only debt transactions can have a recipient");
    if (change.entity === "transaction") {
      await reference(client, "schedule", d.recurringScheduleId);
      if (d.recurringScheduleId && !d.scheduledFor) throw new Error("Recurring transactions require an immutable occurrence date");
    } else {
      if (d.endAt && String(d.endAt) < String(d.startAt)) throw new Error("Recurrence end precedes its start");
      if (existing && scheduleSettings(existing) === scheduleSettings(d)) {
        if (String(existing.lastOccurrenceAt) > String(d.lastOccurrenceAt)) d.lastOccurrenceAt = existing.lastOccurrenceAt;
        if (existing.nextOccurrenceAt == null || d.nextOccurrenceAt != null && String(existing.nextOccurrenceAt) > String(d.nextOccurrenceAt)) { d.nextOccurrenceAt = existing.nextOccurrenceAt; d.nextScheduledFor = existing.nextScheduledFor; }
      }
    }
  }
  if (change.entity === "budget") {
    const account = await reference(client, "account", d.accountId);
    const categoryRows = await Promise.all((d.categoryAssignments as Array<{ categoryId: string }>).map((a) => reference(client, "category", a.categoryId)));
    const budget = createBudget(d as unknown as BudgetInput, { account: account as unknown as Account | null, categories: categoryRows as unknown as Category[] });
    if (!budget.ok) throw new Error(budget.error.message);
    // The account owns one aggregate. A migrated offline draft may carry an older plan ID.
    if (existing) { d.id = existing.id; d.createdAt = existing.createdAt; }
    const { groups, categoryAssignments, ...plan } = d;
    for (const group of groups as Array<{ id: string }>) {
      const rows = await client.execute(sql`select id from budget_groups where id = ${group.id}::uuid and plan_id <> ${d.id}::uuid`);
      if (rows.length) throw new Error("A budget group belongs to another account");
    }

    await write(client, "budget_plans", plan);
    await client.execute(sql`delete from budget_category_assignments where plan_id = ${d.id}::uuid`);
    await client.execute(sql`delete from budget_groups where plan_id = ${d.id}::uuid`);
    for (const group of groups as Record<string, unknown>[]) await write(client, "budget_groups", { ...group, planId: d.id, createdAt: d.createdAt, updatedAt: d.updatedAt });
    for (const assignment of categoryAssignments as Record<string, unknown>[]) await write(client, "budget_category_assignments", { ...assignment, id: crypto.randomUUID(), planId: d.id, createdAt: d.createdAt, updatedAt: d.updatedAt });
    return;
  }
  if (change.entity === "exclusion") {
    if (change.key !== occurrenceId(String(d.scheduleId), new Date(String(d.scheduledFor)))) throw new Error("Invalid occurrence identity");
    await client.execute(sql`delete from transactions where recurring_schedule_id = ${d.scheduleId}::uuid and scheduled_for = ${d.scheduledFor}::timestamptz`);
  }
  if (existing && change.entity !== "debt" && change.entity !== "exclusion") d.createdAt = existing.createdAt;
  await write(client, tables[change.entity], d);
}

async function write(client: Database, table: string, data: Record<string, unknown>) {
  const values = Object.fromEntries(Object.entries(data).map(([key, value]) => [snake(key), value]));
  const columns = Object.keys(values);
  const names = sql.join(columns.map((key) => sql.identifier(key)), sql`, `);
  const updates = sql.join(columns.filter((key) => key !== "id" && key !== "created_at").map((key) => sql`${sql.identifier(key)} = excluded.${sql.identifier(key)}`), sql`, `);
  await client.execute(sql`insert into ${sql.identifier(table)} (${names}) select ${names} from jsonb_populate_record(null::${sql.identifier(table)}, ${JSON.stringify(values)}::jsonb) on conflict (id) do update set ${updates}`);
}
export function stableJSON(value: unknown): string {
  if (Array.isArray(value)) return `[${value.map(stableJSON).join(",")}]`;
  if (value && typeof value === "object") return `{${Object.entries(value).sort(([a], [b]) => a.localeCompare(b)).map(([key, v]) => `${JSON.stringify(key)}:${stableJSON(v)}`).join(",")}}`;
  return JSON.stringify(value);
}
function comparable(value: Record<string, unknown> | null) {
  return stableJSON(Object.fromEntries(Object.entries(value ?? {}).filter(([key]) => !["createdAt", "updatedAt"].includes(key)).map(([key, v]) => [key, key === "amount" && typeof v === "string" ? v.replace(/\.?(0+)$/, (s) => v.includes(".") ? "" : s) : v])));
}
function scheduleSettings(value: Record<string, unknown>) { return comparable(Object.fromEntries(Object.entries(value).filter(([key]) => !["lastOccurrenceAt", "nextOccurrenceAt", "nextScheduledFor"].includes(key)))); }
function failureMessage(cause: unknown): string {
  const error = cause as { code?: string; message?: string; cause?: { code?: string } };
  if (error.code === "23505" || error.cause?.code === "23505") return "A record with these details already exists. Review the local change.";
  if (error.code === "23503" || error.cause?.code === "23503") return "A referenced record changed. Review the local change.";
  return error.message?.startsWith("Failed query:") ? "This change could not be accepted. Review its values." : error.message ?? "This change could not be accepted";
}
