import { beforeEach, describe, expect, it } from "bun:test";
import { eq } from "drizzle-orm";
import { Elysia } from "elysia";
import { db } from "./infrastructure/db/client.ts";
import { accounts, categories, transactions, recurringSchedules } from "./infrastructure/db/schema/index.ts";
import { createDrizzleSyncRepository } from "./infrastructure/sync/drizzle-sync.repository.ts";
import { createSyncRouter } from "./infrastructure/http/routes/sync.router.ts";
import { createDrizzleTransactionRepository } from "./infrastructure/db/repositories/drizzle-transaction.repository.ts";
import { materializeRecurringSchedule } from "./application/transactions/materialize-recurring-schedule.ts";
import { occurrenceId } from "./domain/transactions/occurrence-id.ts";
import type { SyncChange, SyncMutation, SyncSnapshot } from "./application/sync/sync.repository.ts";

// Reset coverage requires this explicitly selected disposable database.
const suite = Bun.env.RUN_SYNC_DATABASE_TESTS === "1" && Bun.env.DATABASE_URL?.includes("127.0.0.1:55439/sync_test") ? describe : describe.skip;
const repository = createDrizzleSyncRepository(db);
const clientId = crypto.randomUUID();
const now = "2026-01-15T12:00:00.000Z";
let snapshot: SyncSnapshot;
const account = () => ({ id: crypto.randomUUID(), name: `Local ${crypto.randomUUID()}`, type: "checking", currency: "USD", icon: "wallet", iconColor: "blue", sortOrder: 0, createdAt: now, updatedAt: now });
const change = (entity: SyncChange["entity"], data: Record<string, unknown>, baseVersion: string | null = null, key = String(data.id)): SyncChange => ({ entity, key, baseVersion, data });
const mutation = (changes: SyncChange[], rest: Partial<SyncMutation> = {}): SyncMutation => ({ clientId, mutationId: crypto.randomUUID(), generation: snapshot.generation, workspaceId: snapshot.workspaceId, authoredAt: now, changes, ...rest });
const txn = (accountId: string, id: string = crypto.randomUUID()) => ({ id, accountId, kind: "expense", amount: "10.1250", currency: "USD", categoryId: null, debtId: null, recurringScheduleId: null, scheduledFor: null, merchant: null, payee: null, note: null, occurredAt: now, createdAt: now, updatedAt: now });
const schedule = (accountId: string) => ({ id: crypto.randomUUID(), accountId, kind: "expense", amount: "10.1250", currency: "USD", categoryId: null, merchant: null, payee: null, note: null, frequency: "monthly", startAt: "2026-01-31T12:00:00.000Z", lastOccurrenceAt: "2026-01-31T12:00:00.000Z", nextOccurrenceAt: "2026-02-28T12:00:00.000Z", nextScheduledFor: null, endAt: null, createdAt: now, updatedAt: now });
const generate = (id: string, through = "2026-02-28T12:00:00.000Z") => materializeRecurringSchedule({ scheduleId: id, through: new Date(through) }, { transactions: createDrizzleTransactionRepository(db) });

suite("persistent two-way synchronization", () => {
  beforeEach(async () => {
    snapshot = await repository.bootstrap();
    await repository.push(mutation([], { reset: true }));
    snapshot = await repository.bootstrap();
  });
  it("imports original IDs, decimal strings and legacy writes", async () => {
    const a = account();
    await db.insert(accounts).values({ ...a, createdAt: new Date(now), updatedAt: new Date(now), type: "checking" });
    const before = await repository.bootstrap();
    expect(before.records.find(r => r.key === a.id)?.data?.id).toBe(a.id);
    const t = txn(a.id);
    expect((await repository.push(mutation([change("transaction", t)]))).status).toBe("accepted");
    const page = await repository.changes(before.cursor, before.generation);
    expect(page.records.find(r => r.key === t.id)?.data?.amount).toBe("10.1250");
    expect(BigInt(page.cursor)).toBeGreaterThan(BigInt(before.cursor));
  });
  it("replays lost responses without duplication and rejects changed reuse", async () => {
    const a = account(); const request = mutation([change("account", a), change("transaction", txn(a.id))]);
    const saved = await repository.push(request);
    expect(saved.status).toBe("accepted");
    expect(await repository.push(request)).toEqual(saved);
    expect(await db.select().from(transactions)).toHaveLength(1);
    expect((await repository.push({ ...request, authoredAt: "2026-01-16T00:00:00.000Z" })).status).toBe("rejected");
  });
  it("rolls back a transfer or reviewed batch when any record is invalid", async () => {
    const a = account(); const b = account();
    await repository.push(mutation([change("account", a), change("account", b)]));
    const first = txn(a.id); const second = { ...txn(b.id), kind: "income", amount: "-1" };
    expect((await repository.push(mutation([change("transaction", first), change("transaction", second)]))).status).toBe("rejected");
    expect(await db.select().from(transactions)).toHaveLength(0);
    const saved = await repository.push(mutation([change("transaction", first), change("transaction", { ...second, amount: first.amount })]));
    expect(saved.status).toBe("accepted");
    expect(saved.records).toHaveLength(2);
    expect(new Set(saved.records.map(r => r.version)).size).toBe(1);
  });
  it("preserves versions on conflict and permits independent work", async () => {
    const a = account(); const saved = await repository.push(mutation([change("account", a)]));
    const version = saved.records[0]!.version;
    await repository.push(mutation([change("account", { ...a, name: "Server" }, version)]));
    const conflict = await repository.push(mutation([change("account", { ...a, name: "Local" }, version)]));
    expect(conflict.status).toBe("conflict"); expect(conflict.records[0]?.data?.name).toBe("Server");
    expect((await repository.push(mutation([change("account", account())]))).status).toBe("accepted");
    expect((await repository.push(mutation([change("account", { ...a, name: "Local" }, conflict.records[0]!.version)]))).status).toBe("accepted");
  });
  it("journals cascades, cleared relationships and whole budget aggregates", async () => {
    const a = account(); const c = { id: crypto.randomUUID(), name: "Food", kind: "expense", parentId: null, icon: "label", color: "coral", sortOrder: 0, createdAt: now, updatedAt: now };
    const b = { id: crypto.randomUUID(), accountId: a.id, currency: "USD", monthlyLimit: "1000", groups: [], categoryAssignments: [{ categoryId: c.id, groupId: null, limit: "50" }], createdAt: now, updatedAt: now };
    const t = { ...txn(a.id), categoryId: c.id };
    const saved = await repository.push(mutation([change("account", a), change("category", c), change("transaction", t), change("budget", b, null, a.id)]));
    expect(saved.status).toBe("accepted");
    const before = await repository.bootstrap();
    await db.delete(categories).where(eq(categories.id, c.id));
    const page = await repository.changes(before.cursor, before.generation);
    expect(page.records.find(r => r.key === c.id)?.data).toBeNull();
    expect(page.records.find(r => r.key === t.id)?.data?.categoryId).toBeNull();
    expect(page.records.find(r => r.entity === "budget")?.data?.categoryAssignments).toEqual([]);
    await db.delete(accounts).where(eq(accounts.id, a.id));
    const deleted = await repository.changes(page.cursor, snapshot.generation);
    expect(deleted.records.find(r => r.key === t.id)?.data).toBeNull();
    expect(deleted.records.find(r => r.entity === "budget")?.data).toBeNull();
  });
  it("keeps one budget per account and applies updates and clears globally", async () => {
    const a = account(); const b = account(); const changes = [change("account", a), change("account", b)];
    for (const accountId of [a.id, b.id, null]) changes.push(change("budget", { id: crypto.randomUUID(), accountId, currency: "USD", monthlyLimit: "500", groups: [], categoryAssignments: [], createdAt: now, updatedAt: now }, null, accountId ?? "all"));
    const saved = await repository.push(mutation(changes));
    expect(saved.status).toBe("accepted");
    const initial = saved.records.find(r => r.entity === "budget" && r.key === a.id)!;
    expect(initial.data).not.toHaveProperty("month");
    // A migrated offline draft may come from a different legacy month/plan ID.
    const updated = await repository.push(mutation([change("budget", { ...initial.data!, id: crypto.randomUUID(), monthlyLimit: "750" }, initial.version, a.id)]));
    expect(updated.status).toBe("accepted");
    expect(updated.records.find(r => r.key === a.id && r.entity === "budget")?.data).toMatchObject({ id: initial.data!.id, monthlyLimit: "750.0000" });
    expect((await repository.bootstrap()).records.filter(r => r.entity === "budget" && r.data)).toHaveLength(3);
    const stale = await repository.push(mutation([change("budget", { ...initial.data!, monthlyLimit: "900" }, initial.version, a.id)]));
    expect(stale.status).toBe("conflict");
    const cleared = await repository.push(mutation([{ entity: "budget", key: a.id, baseVersion: updated.records.find(r => r.key === a.id && r.entity === "budget")!.version, data: null }]));
    expect(cleared.status).toBe("accepted");
    expect((await repository.bootstrap()).records.filter(r => r.entity === "budget" && r.data).map(r => r.key).sort()).toEqual([b.id, "all"].sort());
  });
  it("serializes revisions by commit order and pages complete commits", async () => {
    await Promise.all(Array.from({ length: 105 }, () => repository.push(mutation([change("account", account())]))));
    const page = await repository.changes(snapshot.cursor, snapshot.generation);
    expect(page.hasMore).toBe(true);
    const next = await repository.changes(page.cursor, snapshot.generation);
    expect(next.hasMore).toBe(false);
    expect(new Set([...page.records, ...next.records].map(r => r.key)).size).toBe(105);
    expect((await repository.changes(next.cursor, snapshot.generation)).records).toEqual([]);
  });
  it("deduplicates simultaneous generation without template conflicts", async () => {
    const a = account(); const s = schedule(a.id);
    const initial = await repository.push(mutation([change("account", a), change("schedule", s)]));
    const version = initial.records.find(r => r.key === s.id)!.version;
    await generate(s.id);
    const generated = { ...txn(a.id, occurrenceId(s.id, new Date(s.nextOccurrenceAt))), occurredAt: s.nextOccurrenceAt, scheduledFor: s.nextOccurrenceAt, recurringScheduleId: s.id };
    const response = await repository.push(mutation([{ ...change("transaction", generated), origin: "generated" }, change("schedule", { ...s, lastOccurrenceAt: s.nextOccurrenceAt, nextOccurrenceAt: "2026-03-31T12:00:00.000Z" }, version)]));
    expect(response.status).toBe("accepted"); expect(await db.select().from(transactions)).toHaveLength(1);
    expect(response.records.find(r => r.key === s.id)?.version).toBe(version);
  });
  it("persists skips after server generation and prevents resurrection", async () => {
    const a = account(); const s = schedule(a.id);
    await repository.push(mutation([change("account", a), change("schedule", s)])); await generate(s.id);
    const id = occurrenceId(s.id, new Date(s.nextOccurrenceAt));
    expect((await repository.push(mutation([change("exclusion", { id, scheduleId: s.id, scheduledFor: s.nextOccurrenceAt })]))).status).toBe("accepted");
    const t = { ...txn(a.id, id), occurredAt: s.nextOccurrenceAt, scheduledFor: s.nextOccurrenceAt, recurringScheduleId: s.id };
    expect((await repository.push(mutation([{ ...change("transaction", t), origin: "generated" }]))).status).toBe("accepted");
    expect(await db.select().from(transactions)).toHaveLength(0);
  });
  it("honors offline stop time after server generation passed the due date", async () => {
    const a = account(); const s = schedule(a.id); const first = await repository.push(mutation([change("account", a), change("schedule", s)]));
    await generate(s.id, "2026-04-30T12:00:00.000Z");
    const response = await repository.push(mutation([{ entity: "schedule", key: s.id, data: null, baseVersion: first.records.find(r => r.key === s.id)!.version }], { recurrenceActions: [{ scheduleId: s.id, action: "occurrenceAndFuture", targetScheduledFor: s.nextOccurrenceAt }], authoredAt: "2026-02-01T00:00:00.000Z" }));
    expect(response.status).toBe("accepted"); expect(await db.select().from(transactions)).toHaveLength(0); expect(await db.select().from(recurringSchedules)).toHaveLength(0);
  });
  it("moves a projected occurrence after its original due date without changing its identity", async () => {
    const a = account(); const s = schedule(a.id); const initial = await repository.push(mutation([change("account", a), change("schedule", s)]));
    await generate(s.id);
    const replacement = "2026-03-03T12:00:00.000Z";
    const response = await repository.push(mutation([change("schedule", { ...s, startAt: replacement, nextOccurrenceAt: replacement, nextScheduledFor: s.nextOccurrenceAt, amount: "20" }, initial.records.find(r => r.key === s.id)!.version)], {
      authoredAt: "2026-02-01T00:00:00.000Z", recurrenceActions: [{ scheduleId: s.id, action: "editUpcoming", targetScheduledFor: s.nextOccurrenceAt, retainedTransactionId: null }],
    }));
    expect(response.status).toBe("accepted"); expect(await db.select().from(transactions)).toHaveLength(0);
    await generate(s.id, replacement);
    const [generated] = await db.select().from(transactions);
    expect(generated?.id).toBe(occurrenceId(s.id, new Date(s.nextOccurrenceAt)));
    expect(generated?.scheduledFor?.toISOString()).toBe(s.nextOccurrenceAt);
    expect(generated?.occurredAt.toISOString()).toBe(replacement); expect(generated?.amount).toBe("20.0000");
  });
  it("keeps reset receipts and rejects old-generation uploads", async () => {
    const first = mutation([change("account", account())]); const saved = await repository.push(first);
    const reset = mutation([], { reset: true }); const deleted = await repository.push(reset);
    expect(deleted.status).toBe("accepted"); expect(await repository.push(reset)).toEqual(deleted); expect(await repository.push(first)).toEqual(saved);
    expect((await repository.push(mutation([change("account", account())]))).status).toBe("conflict"); expect(await db.select().from(accounts)).toHaveLength(0);
    expect((await repository.changes(snapshot.cursor, snapshot.generation)).reset).toBe(true);
    expect((await repository.push(mutation([change("account", account())], { generation: deleted.generation }))).status).toBe("accepted");
  });
  it("serves JSON through the public routes", async () => {
    const router = new Elysia({ prefix: "/api/v1" }).use(createSyncRouter(repository));
    const response = await router.handle(new Request("http://localhost/api/v1/sync/push", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(mutation([change("account", account())])) }));
    expect(response.status).toBe(200); expect(((await response.json()) as { status: string }).status).toBe("accepted");
    const bootstrap = await router.handle(new Request("http://localhost/api/v1/sync/bootstrap")); expect(bootstrap.status).toBe(200); expect(((await bootstrap.json()) as { cursor: string }).cursor).toBeString();
  });
});
