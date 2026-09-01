import { sql } from "drizzle-orm";
import {
  type AnyPgColumn,
  boolean,
  index,
  integer,
  numeric,
  pgEnum,
  pgTable,
  text,
  timestamp,
  uniqueIndex,
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

export const categories = pgTable(
  "categories",
  {
    id: uuid("id").defaultRandom().primaryKey(),
    systemKey: varchar("system_key", { length: 80 }),
    name: varchar("name", { length: 80 }).notNull(),
    kind: transactionKind("kind").notNull(),
    parentId: uuid("parent_id").references((): AnyPgColumn => categories.id, {
      onDelete: "cascade",
    }),
    icon: varchar("icon", { length: 80 }),
    color: varchar("color", { length: 20 }),
    isSystem: boolean("is_system").default(false).notNull(),
    examples: text("examples")
      .array()
      .default(sql`'{}'::text[]`)
      .notNull(),
    sortOrder: integer("sort_order").default(1_000).notNull(),
    createdAt: timestamp("created_at", { withTimezone: true })
      .defaultNow()
      .notNull(),
    updatedAt: timestamp("updated_at", { withTimezone: true })
      .defaultNow()
      .notNull(),
  },
  (table) => [
    uniqueIndex("categories_system_key_unique").on(table.systemKey),
    uniqueIndex("categories_root_kind_name_unique")
      .on(
        table.kind,
        sql`lower(${table.name})`,
      )
      .where(sql`${table.parentId} is null`),
    uniqueIndex("categories_parent_name_unique")
      .on(
        table.parentId,
        sql`lower(${table.name})`,
      )
      .where(sql`${table.parentId} is not null`),
    index("categories_parent_id_idx").on(table.parentId),
    index("categories_kind_sort_order_idx").on(table.kind, table.sortOrder),
  ],
);

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
    categoryId: uuid("category_id").references(() => categories.id, {
      onDelete: "set null",
    }),
    merchant: text("merchant"),
    payee: text("payee"),
    description: text("description"),
    normalizedDescription: text("normalized_description"),
    note: text("note"),
    occurredAt: timestamp("occurred_at", { withTimezone: true }).notNull(),
    createdAt: timestamp("created_at", { withTimezone: true })
      .defaultNow()
      .notNull(),
    updatedAt: timestamp("updated_at", { withTimezone: true })
      .defaultNow()
      .notNull(),
  },
  (table) => [
    index("transactions_account_id_idx").on(table.accountId),
    index("transactions_category_id_idx").on(table.categoryId),
    index("transactions_occurred_at_idx").on(table.occurredAt),
    index("transactions_kind_normalized_description_idx").on(
      table.kind,
      table.normalizedDescription,
    ),
    index("transactions_normalized_description_trgm_idx")
      .using(
        "gist",
        table.normalizedDescription.asc().op("gist_trgm_ops"),
      )
      .where(sql`${table.normalizedDescription} is not null`),
  ],
);

export type Account = typeof accounts.$inferSelect;
export type NewAccount = typeof accounts.$inferInsert;
export type Category = typeof categories.$inferSelect;
export type NewCategory = typeof categories.$inferInsert;
export type Transaction = typeof transactions.$inferSelect;
export type NewTransaction = typeof transactions.$inferInsert;
