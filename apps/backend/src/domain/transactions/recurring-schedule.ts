import type { TransactionKind } from "../categories/category.ts";
import type { RecurrenceFrequency } from "./transaction.ts";

export type RecurringSchedule = {
  id: string;
  accountId: string;
  kind: TransactionKind;
  amount: string;
  currency: string;
  categoryId: string | null;
  merchant: string | null;
  payee: string | null;
  note: string | null;
  frequency: RecurrenceFrequency;
  startAt: Date;
  lastOccurrenceAt: Date;
  nextOccurrenceAt: Date | null;
  endAt: Date | null;
  createdAt: Date;
  updatedAt: Date;
};

export type RecurringScheduleValues = Omit<
  RecurringSchedule,
  "id" | "createdAt" | "updatedAt"
>;
