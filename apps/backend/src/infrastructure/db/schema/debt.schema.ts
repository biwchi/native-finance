import { pgTable, text, uuid } from "drizzle-orm/pg-core";

export const debts = pgTable("debts", {
  id: uuid().defaultRandom().primaryKey(),
  name: text().notNull(),
  icon: text().notNull().default("user"),
  color: text().notNull().default("blue"),
});
