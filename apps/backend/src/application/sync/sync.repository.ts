export const syncEntities = ["account", "category", "debt", "transaction", "schedule", "budget", "exclusion"] as const;
export type SyncEntity = typeof syncEntities[number];
export type SyncRecord = { entity: SyncEntity; key: string; version: string; data: Record<string, unknown> | null };
export type SyncChange = Omit<SyncRecord, "version"> & { baseVersion: string | null; origin?: "generated" };
export type SyncRecurrenceAction = { scheduleId: string; action: "occurrence" | "stopRepeating" | "occurrenceAndFuture" | "editUpcoming"; targetScheduledFor: string; retainedTransactionId?: string | null; effectiveAt?: string };
export type SyncMutation = {
  clientId: string; mutationId: string; generation: number; authoredAt: string;
  changes: SyncChange[]; reset?: boolean; workspaceId?: string; recurrenceActions?: SyncRecurrenceAction[];
};
export type SyncResult = {
  mutationId: string; status: "accepted" | "conflict" | "rejected";
  generation: number; records: SyncRecord[]; message?: string;
};
export type SyncSnapshot = { workspaceId: string; generation: number; cursor: string; records: SyncRecord[] };
export interface SyncRepository {
  bootstrap(): Promise<SyncSnapshot>;
  changes(cursor: string, generation: number): Promise<SyncSnapshot & { hasMore: boolean; reset: boolean }>;
  push(mutation: SyncMutation): Promise<SyncResult>;
}
