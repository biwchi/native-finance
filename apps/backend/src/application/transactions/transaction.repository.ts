import type { CategorySummary } from "../../domain/categories/category.ts";
import type {
  RecurringSchedule,
  RecurringScheduleValues,
} from "../../domain/transactions/recurring-schedule.ts";
import type {
  TransactionRecord,
  TransactionResponse,
  TransactionValues,
} from "../../domain/transactions/transaction.ts";

export type ScheduleView = RecurringSchedule & {
  category: CategorySummary | null;
};

export type RecordedScheduleOccurrence = {
  scheduleId: string;
  occurredAt: Date;
};

export interface TransactionStore {
  findRecord(id: string): Promise<TransactionRecord | null>;
  findDetailed(id: string): Promise<TransactionResponse | null>;
  insertTransaction(values: TransactionValues): Promise<TransactionRecord>;
  insertTransactions(values: TransactionValues[]): Promise<TransactionRecord[]>;
  updateTransaction(
    id: string,
    values: Partial<Omit<TransactionRecord, "id" | "createdAt">>,
  ): Promise<boolean>;
  deleteTransaction(id: string): Promise<boolean>;
  findSchedule(id: string, lock?: boolean): Promise<RecurringSchedule | null>;
  insertSchedule(values: RecurringScheduleValues): Promise<RecurringSchedule>;
  updateSchedule(
    id: string,
    values: Partial<Omit<RecurringSchedule, "id" | "createdAt">>,
  ): Promise<void>;
  deleteSchedule(id: string): Promise<void>;
  findFirstRecordedFuture(
    scheduleId: string,
    after: Date,
  ): Promise<TransactionRecord | null>;
  findRecordedOccurrence(
    scheduleId: string,
    occurredAt: Date,
  ): Promise<TransactionRecord | null>;
  deleteFutureTransactions(
    scheduleId: string,
    after: Date,
    excludeId?: string,
  ): Promise<void>;
  insertOccurrences(
    schedule: RecurringSchedule,
    dates: Date[],
  ): Promise<void>;
}

export interface TransactionRepository extends TransactionStore {
  listDetailed(accountId?: string): Promise<TransactionResponse[]>;
  listSchedules(accountId?: string): Promise<ScheduleView[]>;
  listRecordedFuture(
    accountId: string | undefined,
    after: Date,
  ): Promise<RecordedScheduleOccurrence[]>;
  findDueSchedules(through: Date): Promise<RecurringSchedule[]>;
  atomically<Value>(
    operation: (store: TransactionStore) => Promise<Value>,
  ): Promise<Value>;
}
