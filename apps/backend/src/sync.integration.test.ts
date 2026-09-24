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
const account = () => ({ id: crypto.randomUUID(), name: `Local ${crypto.randomUUID()}`, initialBalance: "0", currency: "USD", icon: "wallet", iconColor: "blue", sortOrder: 0, createdAt: now, updatedAt: now });
const change = (entity: SyncChange["entity"], data: Record<string, unknown>, baseVersion: string | null = null, key = String(data.id)): SyncChange => ({ entity, key, baseVersion, data });
const mutation = (changes: SyncChange[], rest: Partial<SyncMutation> = {}): SyncMutation => ({ clientId, mutationId: crypto.randomUUID(), generation: snapshot.generation, workspaceId: snapshot.workspaceId, authoredAt: now, changes, ...rest });
const txn = (accountId: string, id: string = crypto.randomUUID()) => ({ id, accountId, kind: "expense", amount: "10.1250", currency: "USD", categoryId: null, debtId: null, recurringScheduleId: null, scheduledFor: null, counterparty: null, note: null, occurredAt: now, createdAt: now, updatedAt: now });
const schedule = (accountId: string) => ({ id: crypto.randomUUID(), accountId, kind: "expense", amount: "10.1250", currency: "USD", categoryId: null, counterparty: null, note: null, frequency: "monthly", startAt: "2026-01-31T12:00:00.000Z", lastOccurrenceAt: "2026-01-31T12:00:00.000Z", nextOccurrenceAt: "2026-02-28T12:00:00.000Z", nextScheduledFor: null, endAt: null, createdAt: now, updatedAt: now });
const generate = (id: string, through = "2026-02-28T12:00:00.000Z") => materializeRecurringSchedule({ scheduleId: id, through: new Date(through) }, { transactions: createDrizzleTransactionRepository(db) });

suite("persistent two-way synchronization", () => {
  beforeEach(async () => {
    snapshot = await repository.bootstrap();
    await repository.push(mutation([], { reset: true }));
    snapshot = await repository.bootstrap();
  });
  it("syncs the counterparty, clears it, and carries it into recurring payments", async () => {
    const a = account();
    const t = { ...txn(a.id), counterparty: "Urbo Coffee" };
    const plan = { ...schedule(a.id), counterparty: "Subscription business" };
    const saved = await repository.push(mutation([change("account", a), change("transaction", t), change("schedule", plan)]));
    expect(saved.status).toBe("accepted");
    expect(saved.records.find(r => r.key === t.id)?.data?.counterparty).toBe("Urbo Coffee");
    const cleared = await repository.push(mutation([change("transaction", { ...t, counterparty: null }, saved.records.find(r => r.key === t.id)!.version)]));
    expect(cleared.status).toBe("accepted");
    expect(cleared.records.find(r => r.key === t.id)?.data?.counterparty).toBeNull();
    await generate(plan.id);
    const generated = (await repository.bootstrap()).records.find(r => r.entity === "transaction" && r.data?.recurringScheduleId === plan.id)!;
    expect(generated.data?.counterparty).toBe("Subscription business");
    const duplicate = await repository.push(mutation([{ ...change("transaction", generated.data!), origin: "generated" }]));
    expect(duplicate.status).toBe("accepted");
  });

  it("syncs recipient order and keeps it when an older client edits the name", async () => {
    const alice = { id: crypto.randomUUID(), name: "Alice", icon: "user", color: "blue", sortOrder: 0 };
    const zoe = { ...alice, id: crypto.randomUUID(), name: "Zoe", sortOrder: 1 };
    const saved = await repository.push(mutation([change("debt", alice), change("debt", zoe)]));
    expect(saved.status).toBe("accepted");
    const reordered = await repository.push(mutation([
      change("debt", { ...alice, sortOrder: 1 }, saved.records.find(r => r.key === alice.id)!.version),
      change("debt", { ...zoe, sortOrder: 0 }, saved.records.find(r => r.key === zoe.id)!.version),
    ]));
    expect(reordered.status).toBe("accepted");
    const { sortOrder: _, ...legacy } = alice;
    const edited = await repository.push(mutation([
      change("debt", { ...legacy, name: "Renamed" }, reordered.records.find(r => r.key === alice.id)!.version),
    ]));
    expect(edited.status).toBe("accepted");
    expect(edited.records.find(r => r.key === alice.id)?.data).toMatchObject({ name: "Renamed", sortOrder: 1 });
    const added = { ...legacy, id: crypto.randomUUID(), name: "New recipient" };
    const created = await repository.push(mutation([change("debt", added)]));
    expect(created.status).toBe("accepted");
    expect(created.records.find(r => r.key === added.id)?.data?.sortOrder).toBe(2);
    const records = (await repository.bootstrap()).records.filter(r => r.entity === "debt" && r.data);
    expect(records.sort((a, b) => Number(a.data!.sortOrder) - Number(b.data!.sortOrder)).map(r => r.key)).toEqual([zoe.id, alice.id, added.id]);
  });

  it("deletes unused recipients but protects recipients that still have loans", async () => {
    const a = account();
    const recipient = { id: crypto.randomUUID(), name: "Alexey", icon: "user", color: "blue", sortOrder: 0 };
    const loan = { ...txn(a.id), kind: "debt", debtId: recipient.id };
    const saved = await repository.push(mutation([change("account", a), change("debt", recipient), change("transaction", loan)]));
    expect(saved.status).toBe("accepted");
    const removal: SyncChange = { entity: "debt", key: recipient.id, baseVersion: saved.records.find(r => r.key === recipient.id)!.version, data: null };
    const blocked = await repository.push(mutation([removal]));
    expect(blocked.status).toBe("rejected");
    expect(blocked.message).toContain("outstanding loans");
    expect((await repository.bootstrap()).records.find(r => r.key === loan.id)?.data?.amount).toBe("10.1250");
    const returned = await repository.push(mutation([{ entity: "transaction", key: loan.id, baseVersion: saved.records.find(r => r.key === loan.id)!.version, data: null }]));
    expect(returned.status).toBe("accepted");
    const deleted = await repository.push(mutation([removal]));
    expect(deleted.status).toBe("accepted");
    expect(deleted.records.find(r => r.key === recipient.id)?.data).toBeNull();
    expect((await repository.bootstrap()).records.some(r => r.key === recipient.id && r.data)).toBeFalse();
  });
  it("syncs an initial balance once, preserves it on legacy edits, and never creates income", async () => {
    const a = { ...account(), initialBalance: "-1234.5678" };
    const request = mutation([change("account", a)]);
    const saved = await repository.push(request);
    expect(saved.status).toBe("accepted");
    expect(saved.records[0]?.data?.initialBalance).toBe("-1234.5678");
    expect(saved.records[0]?.data).not.toHaveProperty("type");
    expect(await repository.push(request)).toEqual(saved);
    const { initialBalance: _, ...legacy } = a;
    const renamed = await repository.push(mutation([change("account", { ...legacy, name: "Renamed", type: "checking" }, saved.records[0]!.version)]));
    expect(renamed.status).toBe("accepted");
    expect(renamed.records[0]?.data?.initialBalance).toBe("-1234.5678");
    expect(await db.select().from(transactions)).toHaveLength(0);
    const updated = await repository.push(mutation([change("account", { ...a, initialBalance: "999999999999999.9999" }, renamed.records[0]!.version)]));
    expect(updated.records[0]?.data?.initialBalance).toBe("999999999999999.9999");
    expect((await repository.bootstrap()).records.find(r => r.key === a.id)?.data?.initialBalance).toBe("999999999999999.9999");
    const invalid = await repository.push(mutation([change("account", { ...a, initialBalance: "1.23456" }, updated.records[0]!.version)]));
    expect(invalid.status).toBe("rejected");
    expect((await db.select().from(accounts))[0]?.initialBalance).toBe("999999999999999.9999");
  });
  it("imports original IDs, decimal strings and legacy writes", async () => {
    const a = account();
    await db.insert(accounts).values({ ...a, createdAt: new Date(now), updatedAt: new Date(now), initialBalance: "0" });
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

  it("syncs historical currency, offline entries and recurring occurrences after changing account currency", async () => {
    const a = { ...account(), currency: "RUB" };
    const s = { ...schedule(a.id), currency: "RUB", amount: "200" };
    const t = { ...txn(a.id), currency: "RUB", amount: "200" };
    const initial = await repository.push(mutation([change("account", a), change("schedule", s), change("transaction", t)]));
    expect(initial.status).toBe("accepted");
    const accountVersion = initial.records.find(r => r.entity === "account" && r.key === a.id)!.version;
    const changed = await repository.push(mutation([change("account", { ...a, currency: "KZT" }, accountVersion)]));
    expect(changed.status).toBe("accepted");
    expect(changed.records.every(r => r.entity === "account")).toBeTrue();

    const offline = { ...txn(a.id), currency: "RUB", amount: "200" };
    const occurrence = { ...txn(a.id, occurrenceId(s.id, new Date(s.nextOccurrenceAt))), currency: "RUB", amount: "200",
      recurringScheduleId: s.id, scheduledFor: s.nextOccurrenceAt, occurredAt: s.nextOccurrenceAt };
    expect((await repository.push(mutation([change("transaction", offline), { ...change("transaction", occurrence), origin: "generated" }]))).status).toBe("accepted");
    const transactionVersion = initial.records.find(r => r.entity === "transaction" && r.key === t.id)!.version;
    const correction = await repository.push(mutation([change("transaction", { ...t, currency: "KZT" }, transactionVersion)]));
    expect(correction.status).toBe("accepted");
    expect(correction.records.find(r => r.key === t.id)?.data).toMatchObject({ currency: "KZT", amount: "200.0000" });
    const stored = await repository.bootstrap();
    expect(stored.records.find(r => r.key === s.id)?.data?.currency).toBe("RUB");
    expect(stored.records.find(r => r.key === offline.id)?.data?.currency).toBe("RUB");
    expect(stored.records.find(r => r.key === occurrence.id)?.data?.currency).toBe("RUB");
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
  it("accepts repeated deletions after a cascade without masking competing live edits", async () => {
    const a = account(); const t = txn(a.id);
    const saved = await repository.push(mutation([change("account", a), change("transaction", t)]));
    const version = saved.records.find(r => r.entity === "transaction" && r.key === t.id)!.version;
    await db.delete(accounts).where(eq(accounts.id, a.id));
    const removal = mutation([{ entity: "transaction", key: t.id, baseVersion: version, data: null }]);
    const response = await repository.push(removal);
    expect(response.status).toBe("accepted");
    expect(response.records.find(r => r.entity === "transaction" && r.key === t.id)?.data).toBeNull();
    expect(await repository.push(removal)).toEqual(response);
    expect((await repository.push(mutation([{ entity: "transaction", key: crypto.randomUUID(), baseVersion: "1", data: null }]))).status).toBe("accepted");

    const b = account();
    const first = await repository.push(mutation([change("account", b)]));
    const originalVersion = first.records[0]!.version;
    await repository.push(mutation([change("account", { ...b, name: "New name" }, originalVersion)]));
    expect((await repository.push(mutation([{ entity: "account", key: b.id, baseVersion: originalVersion, data: null }]))).status).toBe("conflict");
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
