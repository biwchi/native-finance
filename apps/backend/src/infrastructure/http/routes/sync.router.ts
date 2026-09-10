import { Elysia, t } from "elysia";
import { syncEntities, type SyncRepository } from "../../../application/sync/sync.repository.ts";

const id = t.String({ format: "uuid" });
export function createSyncRouter(repository: SyncRepository) {
  return new Elysia({ prefix: "/sync" })
    .get("/bootstrap", () => repository.bootstrap())
    .get("/changes", ({ query }) => repository.changes(query.cursor, query.generation), {
      query: t.Object({ cursor: t.String({ pattern: "^\\d+$" }), generation: t.Numeric({ minimum: 1 }) }),
    })
    .post("/push", ({ body }) => repository.push(body), {
      body: t.Object({
        workspaceId: t.Optional(id), clientId: id, mutationId: id, generation: t.Integer({ minimum: 1 }),
        authoredAt: t.String({ format: "date-time" }), reset: t.Optional(t.Boolean()),
        recurrenceActions: t.Optional(t.Array(t.Object({
          scheduleId: id, action: t.Union([t.Literal("occurrence"), t.Literal("stopRepeating"), t.Literal("occurrenceAndFuture"), t.Literal("editUpcoming")]),
          effectiveAt: t.Optional(t.String({ format: "date-time" })), targetScheduledFor: t.String({ format: "date-time" }), retainedTransactionId: t.Optional(t.Nullable(id)),
        }), { maxItems: 100 })),
        changes: t.Array(t.Object({
          entity: t.Union(syncEntities.map((entity) => t.Literal(entity))),
          key: t.String({ minLength: 1, maxLength: 100 }),
          baseVersion: t.Nullable(t.String({ pattern: "^\\d+$" })),
          origin: t.Optional(t.Literal("generated")),
          data: t.Nullable(t.Record(t.String(), t.Unknown())),
        }), { maxItems: 10000 }),
      }),
    });
}
