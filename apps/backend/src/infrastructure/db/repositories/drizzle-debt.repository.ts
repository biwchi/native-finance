import { asc, eq } from "drizzle-orm";
import type { DebtRepository } from "../../../domain/debts/debt.ts";
import type { Database } from "../client.ts";
import { debts } from "../schema/debt.schema.ts";

export function createDrizzleDebtRepository(database: Database): DebtRepository {
  return {
    list: () => database.select().from(debts).orderBy(asc(debts.name), asc(debts.id)),
    async findById(id) {
      const [debt] = await database.select().from(debts).where(eq(debts.id, id));
      return debt ?? null;
    },
    async update(id, details) {
      const [debt] = await database.update(debts).set(details).where(eq(debts.id, id)).returning();
      return debt ?? null;
    },
    async create(details) {
      const [debt] = await database.insert(debts).values(details).returning();
      if (!debt) throw new Error("Debt insert did not return a row");
      return debt;
    },
  };
}
