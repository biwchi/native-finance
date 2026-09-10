# Local-first finance data

Apply migrations through 0014 to the backend before distributing the new iOS client. Migrations 0012 and 0013 preserve existing entity IDs, amounts, and schedules. Migration 0014 keeps the budget with the latest `updatedAt` per account, breaking ties by descending ID, preserves its pools and assignments, and removes monthly storage. The existing CRUD API remains available and journals its changes for sync clients.

## iOS storage and saves

`LocalFinanceRepository` owns one GRDB 7.11.1 database at `Application Support/FinanceTracker/finance.sqlite`. The directory uses iOS file protection until first authentication. Schema migrations run before reads. Records have stable IDs, JSON data with decimal monetary strings, server versions and copies, and indexed account/date and relationship columns. Display preferences stay in UserDefaults.

`LocalEditor` validates finance changes and calculates their complete local effects. The repository commits these records and their durable outbox operation together. A failed SQLite transaction leaves both unchanged. Stores publish the committed local snapshot synchronously and continue observing it through GRDB. Account views read the selected account. Budget limits use only the account scope; the selected month filters spending.

Transfers and reviewed Quick Entry drafts form one atomic mutation. Quick Entry prompts and review drafts are stored locally. Its parser receives complete local account and category context, including unsynced entities. Final draft commits do not call the parser or server. Category history matching uses the local ledger.

The outbox retains stable client and mutation UUIDs, original action times, expected record versions, dependencies, attempts, and the next retry time. The single sync worker uploads ready operations in order, then downloads changes. An acknowledgment rebases unsent dependent operations. It cannot overwrite a newer local edit. Incoming records and cursor advancement commit together; malformed pages roll back.

## Server protocol

All routes are below `/api/v1`:

| Route | Contract |
| --- | --- |
| `GET /sync/bootstrap` | Complete `{ workspaceId, generation, cursor, records }` snapshot. |
| `POST /sync/push` | One ordered operation containing typed record changes. Returns its durable acknowledgment, conflict, or rejection. |
| `GET /sync/changes?cursor=…&generation=…` | Committed changes, tombstones, next cursor, `hasMore`, and `reset`. Pages contain complete revisions. |

A mutation contains `clientId`, `mutationId`, `workspaceId`, `generation`, `authoredAt`, `changes`, and optional `reset` and `recurrenceActions`. Each change includes an entity type, key, expected `baseVersion` (null for a new entity), and full data or null for deletion. Entity types are account, category, debt, transaction, schedule, budget, and exclusion. Budget keys are `accountUUID` or `all`; groups and assignments travel inside that aggregate. Automatic occurrence creation carries `origin: generated`.

SQLite migration `global-budgets-v2` collapses legacy monthly budgets using the same ordering. It converts pending budget changes to account keys, gives changed payloads fresh mutation IDs, and connects edits that now share a budget. Existing conflict review preserves local edits when the migrated server budget differs. Clients ignore retired monthly keys in older journal pages. Upgrade the backend before the client; old clients with month-based sync keys must upgrade. The `/budgets/monthly` CRUD endpoint accepts an optional legacy `month` field but ignores it and returns the shared budget without a month.

PostgreSQL serializes finance writes through the workspace row before acquiring domain row locks. Triggers capture ordinary writes, cascades, cleared relationships, and budget aggregate changes in the same transaction. A revision therefore represents a complete committed operation. Bootstrap and delta reads hold a shared workspace lock for a consistent view.

Push validates references and domain values, checks versions, then applies the changes inside a savepoint. The domain changes, journal, and receipt commit together. A repeated client/mutation ID with the same canonical request returns its stored result, including after a reset; different content under the same ID is rejected. Transient database failures remain retryable. V1 retains receipts, change history, and tombstones.

## Recurring entries

Occurrence identity is UUID v5 using the schedule UUID as namespace and the original scheduled UTC instant formatted to milliseconds as the name. `scheduledFor` remains independent of a transaction's displayed date. Imported transaction IDs remain unchanged. `nextScheduledFor` preserves the identity of a projected occurrence whose date changes before it is generated.

Local and server generators use the same identity and persist exclusions for skips/deletions. Progress-only updates do not change the schedule template version. Recurring actions carry their original target and effective time, so server generation passing a due date does not invalidate an offline stop or date edit. Shared fixtures in `fixtures/local-first-recurrence.json` cover identity, month ends, leap days, and deletion behavior.

## Resets and review

Delete all data commits an empty local ledger and a durable reset barrier immediately. Later local operations depend on that reset. Its acknowledgment advances their workspace generation. Repeating an in-flight reset retains its mutation ID, and responses for removed operations are ignored. In-flight AI interpretation is also invalidated by the local reset epoch.

A reset received from another device preserves pending local work for one explicit decision. Keeping this device's data queues it against the new generation; accepting server data restores the current server snapshot.

Temporary network failures remain silent and use persisted exponential backoff with jitter. Conflicts and permanent rejections pause the affected operation and dependents; independent operations continue. Settings contains one Review changes entry. Keeping local changes incorporates later local fixes; accepting the server version also discards dependent operations that would otherwise reference invalid data.

## Exchange rates and lifecycle

The backend and client each reuse successful complete USD-based rate refreshes for 24 hours. Concurrent callers share a request. The existing rate endpoint returns the complete table when filters are absent; filtered requests and AI conversions use the same backend cache. Failed refreshes do not move the success timestamp. Cached rates remain usable across launches, and missing currencies produce unavailable combined totals with original amounts retained.

Sync triggers on launch, foreground entry, restored connectivity, local commits, and `BGAppRefreshTask`. Limited background execution finishes active uploads when possible. iOS controls background scheduling and may suspend or terminate the app before an upload completes; the next run resumes from the durable outbox. There is no promise of a fixed background interval.

## Validation

Use an isolated PostgreSQL database. The sync reset suite deliberately requires `RUN_SYNC_DATABASE_TESTS=1` and a disposable database named `sync_test` at `127.0.0.1:55439`; it must never target the development ledger. Other API tests use `RUN_DATABASE_TESTS=1`. Migration preservation tests require `RUN_MIGRATION_TESTS=1` and `MIGRATION_TEST_DATABASE_URL` ending in `_migration_test`.

```sh
# From apps/backend, with DATABASE_URL explicitly set to the disposable database:
bun run db:migrate
bun run typecheck
RUN_DATABASE_TESTS=1 bun test
RUN_SYNC_DATABASE_TESTS=1 bun test src/sync.integration.test.ts
```

Native XCTest coverage uses file-backed SQLite for commits, relaunches, atomic transfers/batches, dependencies, conflicts, retry recovery, cursor rollback, resets, recurrence, and daily rates. Native rendering and contrast tests cover light/dark appearances and enabled, selected, disabled, and generic loading controls. Pressed interaction states and real-device background delivery need a physical iPhone check. No browser verification is required.

V1 keeps the existing single personal workspace and no-auth backend model. Future clients should use the versioned sync routes. Authentication and workspace membership are separate work before a hosted multi-user release.
