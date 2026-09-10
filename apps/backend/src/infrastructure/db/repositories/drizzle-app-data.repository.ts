import type { AppDataRepository } from "../../../application/settings/app-data.repository.ts";
import { sql } from "drizzle-orm";
import type { Database } from "../client.ts";
import { accounts, budgetPlans, categories, debts } from "../schema/index.ts";

export function createDrizzleAppDataRepository(database: Database): AppDataRepository {
  return {
    async deleteAll() {
      await database.transaction(async (transaction) => {
        await transaction.execute(sql`select finance_sync_lock()`);
        // Account cascades remove transactions and recurring schedules. Delete global
        // plans explicitly as their accountId is null, then all remaining user content.
        await transaction.delete(accounts);
        await transaction.delete(budgetPlans);
        await transaction.delete(debts);
        await transaction.delete(categories);
        await transaction.execute(sql`delete from recurrence_exclusions`);
        await transaction.execute(sql`update sync_workspace set generation = generation + 1 where id = 1`);
      });
    },
  };
}
