import { sql } from "drizzle-orm";
import {
  type AnyPgColumn,
  boolean,
  index,
  integer,
  pgTable,
  text,
  timestamp,
  uniqueIndex,
  uuid,
  varchar,
} from "drizzle-orm/pg-core";

import { transactionKind } from "./enums.schema.ts";

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
    examples: text().array().default(sql`'{}'::text[]`).notNull(),
    sortOrder: integer().default(1_000).notNull(),
    createdAt: timestamp({ withTimezone: true }).defaultNow().notNull(),
    updatedAt: timestamp({ withTimezone: true }).defaultNow().notNull(),
  },
  (table) => [
    uniqueIndex("categories_system_key_unique").on(table.systemKey),
    uniqueIndex("categories_root_kind_name_unique")
      .on(table.kind, sql`lower(${table.name})`)
      .where(sql`${table.parentId} is null`),
    uniqueIndex("categories_parent_name_unique")
      .on(table.parentId, sql`lower(${table.name})`)
      .where(sql`${table.parentId} is not null`),
    index("categories_parent_id_idx").on(table.parentId),
    index("categories_kind_sort_order_idx").on(table.kind, table.sortOrder),
  ],
);
