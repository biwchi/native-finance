import { beforeEach, describe, expect, it } from "bun:test";
import { sql } from "drizzle-orm";
import { db } from "./infrastructure/db/client.ts";
import { createDrizzleSyncRepository } from "./infrastructure/sync/drizzle-sync.repository.ts";
import type { SyncChange, SyncMutation, SyncSnapshot } from "./application/sync/sync.repository.ts";

const suite = Bun.env.RUN_SYNC_DATABASE_TESTS === "1" && Bun.env.DATABASE_URL?.includes("127.0.0.1:55439/sync_test") ? describe : describe.skip;
const repository = createDrizzleSyncRepository(db);
let snapshot: SyncSnapshot;
const now = "2026-09-22T12:00:00.000Z";
const account = () => ({ id: crypto.randomUUID(), name: "Dream car", initialBalance: "14000.0000", currency: "USD", icon: "car", iconColor: "blue", sortOrder: 0, createdAt: now, updatedAt: now });
const goal = (accountId: string) => ({ id: crypto.randomUUID(), accountId, name: "Dream car", targetAmount: "25000.1234", icon: "car", color: "blue", deadline: "2028-02-29", sortOrder: 0, createdAt: now, updatedAt: now });
const change = (entity: SyncChange["entity"], data: Record<string, unknown>, baseVersion: string | null = null): SyncChange => ({ entity, key: String(data.id), data, baseVersion });
const mutation = (changes: SyncChange[], reset = false): SyncMutation => ({ clientId: crypto.randomUUID(), mutationId: crypto.randomUUID(), workspaceId: snapshot.workspaceId, generation: snapshot.generation, authoredAt: now, changes, reset });

suite("goal persistence and synchronization", () => {
  beforeEach(async () => {
    snapshot = await repository.bootstrap();
    await repository.push(mutation([], true));
    snapshot = await repository.bootstrap();
  });

  it("creates, bootstraps, edits, and reorders multiple goals without touching money", async () => {
    const a = account(), first = goal(a.id), second = { ...goal(a.id), name: "Another goal", sortOrder: 1 };
    const request = mutation([change("goal", first), change("goal", second), change("account", a)]);
    const saved = await repository.push(request);
    expect(saved.status).toBe("accepted");
    expect(await repository.push(request)).toEqual(saved);
    expect(saved.records.find(r => r.key === first.id)?.data).toMatchObject({ targetAmount: "25000.1234", deadline: "2028-02-29" });
    const updated = await repository.push(mutation([
      change("goal", { ...first, name: "Car", sortOrder: 1, deadline: null }, saved.records.find(r => r.key === first.id)!.version),
      change("goal", { ...second, sortOrder: 0 }, saved.records.find(r => r.key === second.id)!.version),
    ]));
    expect(updated.status).toBe("accepted");
    const records = (await repository.bootstrap()).records;
    expect(records.filter(r => r.entity === "goal" && r.data).sort((a, b) => Number(a.data!.sortOrder) - Number(b.data!.sortOrder)).map(r => r.key)).toEqual([second.id, first.id]);
    expect(records.find(r => r.key === first.id)?.data?.deadline).toBeNull();
    expect(records.find(r => r.key === a.id)?.data?.initialBalance).toBe("14000.0000");
    expect(records.some(r => r.entity === "transaction" && r.data)).toBeFalse();
  });

  it("rejects missing accounts and preserves the server goal on a stale edit", async () => {
    const a = account(), g = goal(a.id);
    expect((await repository.push(mutation([change("goal", g)]))).status).toBe("rejected");
    const saved = await repository.push(mutation([change("account", a), change("goal", g)]));
    const version = saved.records.find(r => r.key === g.id)!.version;
    expect((await repository.push(mutation([change("goal", { ...g, name: "Updated" }, version)]))).status).toBe("accepted");
    expect((await repository.push(mutation([change("goal", { ...g, name: "Stale" }, version)]))).status).toBe("conflict");
    expect((await repository.bootstrap()).records.find(r => r.key === g.id)?.data?.name).toBe("Updated");
  });

  it("keeps the account when deleting a goal and journals account cascades", async () => {
    const a = account(), first = goal(a.id), second = goal(a.id);
    const saved = await repository.push(mutation([change("account", a), change("goal", first), change("goal", second)]));
    const removed = await repository.push(mutation([{ entity: "goal", key: first.id, data: null, baseVersion: saved.records.find(r => r.key === first.id)!.version }]));
    expect(removed.status).toBe("accepted");
    expect(removed.records.find(r => r.key === first.id)?.data).toBeNull();
    expect((await repository.bootstrap()).records.find(r => r.key === a.id)?.data?.initialBalance).toBe("14000.0000");
    // An ordinary CRUD deletion must also publish the goal tombstone.
    await db.execute(sql`delete from accounts where id = ${a.id}::uuid`);
    const page = await repository.changes(snapshot.cursor, snapshot.generation);
    expect(page.records.find(r => r.key === second.id && r.data === null)).toBeDefined();
    expect((await repository.bootstrap()).records.some(r => r.entity === "goal" && r.data)).toBeFalse();
  });

  it("clears goals on workspace reset", async () => {
    const a = account();
    await repository.push(mutation([change("account", a), change("goal", goal(a.id))]));
    expect((await repository.push(mutation([], true))).status).toBe("accepted");
    expect((await repository.bootstrap()).records.some(r => r.entity === "goal" && r.data)).toBeFalse();
  });
});
