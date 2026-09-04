import { sql } from "drizzle-orm";
import {
  check,
  date,
  index,
  integer,
  numeric,
  pgTable,
  timestamp,
  uniqueIndex,
  uuid,
  varchar,
} from "drizzle-orm/pg-core";

import { accounts } from "./account.schema.ts";
import { categories } from "./category.schema.ts";

export const budgetPlans = pgTable(
  "budget_plans",
  {
    id: uuid().defaultRandom().primaryKey(),
    accountId: uuid().references(() => accounts.id, { onDelete: "cascade" }),
    month: date({ mode: "string" }).notNull(),
    currency: varchar({ length: 3 }).notNull(),
    monthlyLimit: numeric({ precision: 19, scale: 4 }),
    createdAt: timestamp({ withTimezone: true }).defaultNow().notNull(),
    updatedAt: timestamp({ withTimezone: true }).defaultNow().notNull(),
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
    planId: uuid().notNull().references(() => budgetPlans.id, {
      onDelete: "cascade",
    }),
    name: varchar({ length: 80 }).notNull(),
    limit: numeric({ precision: 19, scale: 4 }).notNull(),
    sortOrder: integer().default(0).notNull(),
    createdAt: timestamp({ withTimezone: true }).defaultNow().notNull(),
    updatedAt: timestamp({ withTimezone: true }).defaultNow().notNull(),
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
    planId: uuid().notNull().references(() => budgetPlans.id, {
      onDelete: "cascade",
    }),
    groupId: uuid().references(() => budgetGroups.id, { onDelete: "cascade" }),
    categoryId: uuid().notNull().references(() => categories.id, {
      onDelete: "cascade",
    }),
    limit: numeric({ precision: 19, scale: 4 }),
    createdAt: timestamp({ withTimezone: true }).defaultNow().notNull(),
    updatedAt: timestamp({ withTimezone: true }).defaultNow().notNull(),
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
