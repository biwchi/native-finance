import { pgEnum } from "drizzle-orm/pg-core";

export const transactionKind = pgEnum("transaction_kind", [
  "expense",
  "income",
  "debt",
]);

export const recurrenceFrequency = pgEnum("recurrence_frequency", [
  "daily",
  "weekly",
  "monthly",
  "yearly",
]);
