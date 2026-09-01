import { sql } from "drizzle-orm";
import {
  type AnyPgColumn,
  boolean,
  check,
  date,
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
  id: uuid().defaultRandom().primaryKey(),
  name: varchar({ length: 120 }).notNull(),
  type: accountType().notNull(),
  currency: varchar({ length: 3 }).notNull(),
  icon: varchar({ length: 80 }).default("creditcard.fill").notNull(),
  iconColor: varchar({ length: 20 }).default("blue").notNull(),
  createdAt: timestamp({ withTimezone: true })
    .defaultNow()
    .notNull(),
  updatedAt: timestamp({ withTimezone: true })
    .defaultNow()
    .notNull(),
});

export const categories = pgTable(
  "categories",
  {
    id: uuid().defaultRandom().primaryKey(),
    systemKey: varchar({ length: 80 }),
    name: varchar({ length: 80 }).notNull(),
    kind: transactionKind().notNull(),
    parentId: uuid().references((): AnyPgColumn => categories.id, {
      onDelete: "cascade",
    }),
    icon: varchar({ length: 80 }),
    color: varchar({ length: 20 }),
    isSystem: boolean().default(false).notNull(),
    examples: text()
      .array()
      .default(sql`'{}'::text[]`)
      .notNull(),
    sortOrder: integer().default(1_000).notNull(),
    createdAt: timestamp({ withTimezone: true })
      .defaultNow()
      .notNull(),
    updatedAt: timestamp({ withTimezone: true })
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
    id: uuid().defaultRandom().primaryKey(),
    accountId: uuid()
      .notNull()
      .references(() => accounts.id, { onDelete: "cascade" }),
    kind: transactionKind().notNull(),
    amount: numeric({ precision: 19, scale: 4 }).notNull(),
    currency: varchar({ length: 3 }).notNull(),
    categoryId: uuid().references(() => categories.id, {
      onDelete: "set null",
    }),
    merchant: text(),
    payee: text(),
    description: text(),
    normalizedDescription: text(),
    note: text(),
    occurredAt: timestamp({ withTimezone: true }).notNull(),
    createdAt: timestamp({ withTimezone: true })
      .defaultNow()
      .notNull(),
    updatedAt: timestamp({ withTimezone: true })
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

export const budgetPlans = pgTable(
  "budget_plans",
  {
    id: uuid().defaultRandom().primaryKey(),
    accountId: uuid().references(() => accounts.id, {
      onDelete: "cascade",
    }),
    month: date({ mode: "string" }).notNull(),
    currency: varchar({ length: 3 }).notNull(),
    monthlyLimit: numeric({ precision: 19, scale: 4 }),
    createdAt: timestamp({ withTimezone: true })
      .defaultNow()
      .notNull(),
    updatedAt: timestamp({ withTimezone: true })
      .defaultNow()
      .notNull(),
  },
  (table) => [
    uniqueIndex("budget_plans_account_month_unique")
      .on(table.accountId, table.month)
      .where(sql`${table.accountId} is not null`),
    uniqueIndex("budget_plans_all_accounts_month_unique")
      .on(table.month)
      .where(sql`${table.accountId} is null`),
    check(
      "budget_plans_monthly_limit_positive",
      sql`${table.monthlyLimit} is null or ${table.monthlyLimit} > 0`,
    ),
  ],
);

export const budgetGroups = pgTable(
  "budget_groups",
  {
    id: uuid().primaryKey(),
    planId: uuid()
      .notNull()
      .references(() => budgetPlans.id, { onDelete: "cascade" }),
    name: varchar({ length: 80 }).notNull(),
    limit: numeric({ precision: 19, scale: 4 }).notNull(),
    sortOrder: integer().default(0).notNull(),
    createdAt: timestamp({ withTimezone: true })
      .defaultNow()
      .notNull(),
    updatedAt: timestamp({ withTimezone: true })
      .defaultNow()
      .notNull(),
  },
  (table) => [
    index("budget_groups_plan_id_idx").on(table.planId),
    uniqueIndex("budget_groups_plan_name_unique").on(
      table.planId,
      sql`lower(${table.name})`,
    ),
    check("budget_groups_limit_positive", sql`${table.limit} > 0`),
  ],
);

export const budgetCategoryAssignments = pgTable(
  "budget_category_assignments",
  {
    id: uuid().defaultRandom().primaryKey(),
    planId: uuid()
      .notNull()
      .references(() => budgetPlans.id, { onDelete: "cascade" }),
    groupId: uuid().references(() => budgetGroups.id, {
      onDelete: "cascade",
    }),
    categoryId: uuid()
      .notNull()
      .references(() => categories.id, { onDelete: "cascade" }),
    limit: numeric({ precision: 19, scale: 4 }),
    createdAt: timestamp({ withTimezone: true })
      .defaultNow()
      .notNull(),
    updatedAt: timestamp({ withTimezone: true })
      .defaultNow()
      .notNull(),
  },
  (table) => [
    uniqueIndex("budget_category_assignments_plan_category_unique").on(
      table.planId,
      table.categoryId,
    ),
    index("budget_category_assignments_group_id_idx").on(table.groupId),
    index("budget_category_assignments_category_id_idx").on(table.categoryId),
    check(
      "budget_category_assignment_has_destination",
      sql`${table.groupId} is not null or ${table.limit} is not null`,
    ),
    check(
      "budget_category_assignment_limit_positive",
      sql`${table.limit} is null or ${table.limit} > 0`,
    ),
  ],
);

export type Account = typeof accounts.$inferSelect;
export type NewAccount = typeof accounts.$inferInsert;
export type Category = typeof categories.$inferSelect;
export type NewCategory = typeof categories.$inferInsert;
export type Transaction = typeof transactions.$inferSelect;
export type NewTransaction = typeof transactions.$inferInsert;
export type BudgetPlan = typeof budgetPlans.$inferSelect;
export type NewBudgetPlan = typeof budgetPlans.$inferInsert;
export type BudgetGroup = typeof budgetGroups.$inferSelect;
export type BudgetCategoryAssignment = typeof budgetCategoryAssignments.$inferSelect;
