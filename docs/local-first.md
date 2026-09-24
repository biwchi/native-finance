# Local-first finance data

Apply migrations through 0017 to the backend before distributing the new iOS client. Migrations 0012 and 0013 preserve existing entity IDs, amounts, and schedules. Migration 0014 keeps the budget with the latest `updatedAt` per account, breaking ties by descending ID, preserves its pools and assignments, and removes monthly storage. Migration 0015 removes the unused account type, adds `initialBalance` as a signed decimal string with a zero default, and refreshes account sync snapshots. Initial balances are account metadata and never create income or expense entries. Older local records decode a missing balance as zero; old queued edits that omit it preserve the server's value. Upgrade the backend before this client. The existing CRUD API remains available and journals its changes for sync clients.

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

A mutation contains `clientId`, `mutationId`, `workspaceId`, `generation`, `authoredAt`, `changes`, and optional `reset` and `recurrenceActions`. Each change includes an entity type, key, expected `baseVersion` (null for a new entity), and full data or null for deletion. Entity types are account, category, debt, transaction, schedule, budget, exclusion, and goal. Budget keys are `accountUUID` or `all`; groups and assignments travel inside that aggregate. Automatic occurrence creation carries `origin: generated`.

SQLite migration `global-budgets-v2` collapses legacy monthly budgets using the same ordering. It converts pending budget changes to account keys, gives changed payloads fresh mutation IDs, and connects edits that now share a budget. Existing conflict review preserves local edits when the migrated server budget differs. Clients ignore retired monthly keys in older journal pages. Upgrade the backend before the client; old clients with month-based sync keys must upgrade. The `/budgets/monthly` CRUD endpoint accepts an optional legacy `month` field but ignores it and returns the shared budget without a month.

PostgreSQL serializes finance writes through the workspace row before acquiring domain row locks. Triggers capture ordinary writes, cascades, cleared relationships, and budget aggregate changes in the same transaction. A revision therefore represents a complete committed operation. Bootstrap and delta reads hold a shared workspace lock for a consistent view.

Push validates references and domain values, checks versions, then applies the changes inside a savepoint. The domain changes, journal, and receipt commit together. A repeated client/mutation ID with the same canonical request returns its stored result, including after a reset; different content under the same ID is rejected. Transient database failures remain retryable. V1 retains receipts, change history, and tombstones.

## Savings goals

Migration 0017 adds goals and journals their writes and account-deletion cascades. Apply it before running a client that creates goals. All clients sharing a workspace must understand the `goal` sync entity before goals are created there.

Goals live in Finances. Each has a name, positive target amount, linked account, icon, color, optional deadline, and saved manual order. Multiple goals may use the same account; each independently compares its target with that account's full balance. Saving a goal never moves money. Existing initial balances, income, spending, debts, transfers, and exchange-rate conversion feed progress through `TransactionStore.balance`. Missing rates show an unavailable balance instead of partial progress. Completion is derived from the current balance, can reverse after spending, and does not change the saved order.

Targets use the linked account's currency. Changing the account or its currency keeps the numeric target and interprets it in the new currency, like the account's initial balance; no currency conversion is applied to the target. Deadlines are nullable `YYYY-MM-DD` calendar days, not UTC timestamps. They do not lock or expire a goal.

The editor focuses the name immediately, places the existing account menu and calendar popover at opposite sides of the first row, and shows the shared color and icon pickers inline. Close and swipe-dismiss discard the unsaved draft immediately. Deleting a goal requires confirmation and preserves the account and its money. Deleting an account removes its linked goals, and the account confirmation names that effect. Goal details open the existing income entry sheet for top-ups.

Goal records and reorder operations use the same atomic local commit, dependency tracking, durable outbox, conflict review, and workspace reset paths as other finance data. No SQLite schema change is required for the generic record store.

## Recurring entries

Occurrence identity is UUID v5 using the schedule UUID as namespace and the original scheduled UTC instant formatted to milliseconds as the name. `scheduledFor` remains independent of a transaction's displayed date. Imported transaction IDs remain unchanged. `nextScheduledFor` preserves the identity of a projected occurrence whose date changes before it is generated.

Local and server generators use the same identity and persist exclusions for skips/deletions. Progress-only updates do not change the schedule template version. Recurring actions carry their original target and effective time, so server generation passing a due date does not invalidate an offline stop or date edit. Shared fixtures in `fixtures/local-first-recurrence.json` cover identity, month ends, leap days, and deletion behavior.

## Resets and review

Delete all data commits an empty local ledger and a durable reset barrier immediately. Later local operations depend on that reset. Its acknowledgment advances their workspace generation. Repeating an in-flight reset retains its mutation ID, and responses for removed operations are ignored. In-flight AI interpretation is also invalidated by the local reset epoch.

A reset received from another device preserves pending local work for one explicit decision. Keeping this device's data queues it against the new generation; accepting server data restores the current server snapshot.

Temporary network failures remain silent and use persisted exponential backoff with jitter. Conflicts and permanent rejections pause the affected operation and dependents; independent operations continue. Deleting an already absent record succeeds even if the deletion's original version is stale. A deletion against an existing, changed record still conflicts.

After downloading changes, a paused queue triggers a complete bootstrap snapshot once per changed queue/cursor. The client can retire a paused operation and its dependents only when the latest queued effects explicitly delete every affected financial record, those records are absent locally and in the complete snapshot, and no upload has an uncertain outcome or unresolved outside dependency. Recurrence actions require their deleted schedules to be absent too; exclusions for those schedules are then obsolete. A missing cached copy alone never proves deletion. Workspace resets, stale snapshots, and surviving local entries prevent automatic retirement.

Settings contains one Review changes entry. Related operations, including shared dependents, appear together with their latest saved details. Missing server copies are distinguished from confirmed removals, and storage read failures remain errors. Missing references preserve the saved work and offer export rather than a retry that cannot repair the reference. Exports contain saved entries and original queued operations as JSON. For other conflicts, keeping the iPhone's changes incorporates later local fixes. Discarding requires a second screen listing the affected entries and available synced copies; the decision covers the whole displayed dependency group. Completed deletions need no user decision.

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

## Person or business

Transactions and recurring schedules use one nullable `counterparty` field. AI extraction, the editor, local storage, sync and CSV use that same field. Blank values are stored as null; clearing the editor clears the stored value.

This pre-production change updates the existing database setup scripts and removes merchant/payee storage. Reset the development backend database and the iOS app's local data before using this version. No compatibility migration or backfill is provided. Apply backend setup through 0017 before starting the updated client.
