import {
  date,
  index,
  numeric,
  pgEnum,
  pgTable,
  text,
  timestamp,
  uuid,
  varchar,
} from "drizzle-orm/pg-core";

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

export const accounts = pgTable("accounts", {
  id: uuid("id").defaultRandom().primaryKey(),
  name: varchar("name", { length: 120 }).notNull(),
  type: accountType("type").notNull(),
  currency: varchar("currency", { length: 3 }).notNull(),
  icon: varchar("icon", { length: 80 }).default("creditcard.fill").notNull(),
  iconColor: varchar("icon_color", { length: 20 }).default("blue").notNull(),
  createdAt: timestamp("created_at", { withTimezone: true })
    .defaultNow()
    .notNull(),
  updatedAt: timestamp("updated_at", { withTimezone: true })
    .defaultNow()
    .notNull(),
});

export const transactions = pgTable(
  "transactions",
  {
    id: uuid("id").defaultRandom().primaryKey(),
    accountId: uuid("account_id")
      .notNull()
      .references(() => accounts.id, { onDelete: "cascade" }),
    kind: transactionKind("kind").notNull(),
    amount: numeric("amount", { precision: 19, scale: 4 }).notNull(),
    currency: varchar("currency", { length: 3 }).notNull(),
    category: varchar("category", { length: 80 }),
    note: text("note"),
    occurredOn: date("occurred_on", { mode: "string" }).notNull(),
    createdAt: timestamp("created_at", { withTimezone: true })
      .defaultNow()
      .notNull(),
    updatedAt: timestamp("updated_at", { withTimezone: true })
      .defaultNow()
      .notNull(),
  },
  (table) => [
    index("transactions_account_id_idx").on(table.accountId),
    index("transactions_occurred_on_idx").on(table.occurredOn),
  ],
);

export type Account = typeof accounts.$inferSelect;
export type NewAccount = typeof accounts.$inferInsert;
export type Transaction = typeof transactions.$inferSelect;
export type NewTransaction = typeof transactions.$inferInsert;
