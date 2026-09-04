import { pgEnum } from "drizzle-orm/pg-core";

export const accountType = pgEnum("account_type", [
  "cash",
  "checking",
  "savings",
  "credit",
  "investment",
]);

export const transactionKind = pgEnum("transaction_kind", [
  "expense",
  "income",
]);

export const recurrenceFrequency = pgEnum("recurrence_frequency", [
  "daily",
  "weekly",
  "monthly",
  "yearly",
]);
