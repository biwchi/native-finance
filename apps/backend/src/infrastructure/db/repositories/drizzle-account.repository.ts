import { asc, eq, sql } from "drizzle-orm";

import type { AccountRepository } from "../../../application/accounts/account.repository.ts";
import type { AccountDetails } from "../../../domain/accounts/account.ts";
import type { Database } from "../client.ts";
import { accounts } from "../schema/account.schema.ts";

export function createDrizzleAccountRepository(
  database: Database,
): AccountRepository {
  const list = () => database
    .select()
    .from(accounts)
    .orderBy(asc(accounts.sortOrder), asc(accounts.name), asc(accounts.createdAt));

  return {
    list,

    async findById(id) {
      const [account] = await database
        .select()
        .from(accounts)
        .where(eq(accounts.id, id))
        .limit(1);
      return account ?? null;
    },

    async create(details: AccountDetails) {
      const [sortOrderResult] = await database
        .select({
          nextSortOrder: sql<number>`coalesce(max(${accounts.sortOrder}), -1) + 1`,
        })
        .from(accounts);
      const [account] = await database
        .insert(accounts)
        .values({
          ...details,
          sortOrder: sortOrderResult?.nextSortOrder ?? 0,
        })
        .returning();

      if (!account) throw new Error("Account insert did not return a row");
      return account;
    },

    async update(id, details) {
      const [account] = await database
        .update(accounts)
        .set({ ...details, updatedAt: new Date() })
        .where(eq(accounts.id, id))
        .returning();
      return account ?? null;
    },

    async delete(id) {
      const [deleted] = await database
        .delete(accounts)
        .where(eq(accounts.id, id))
        .returning({ id: accounts.id });
      return Boolean(deleted);
    },

    async replaceOrder(accountIds) {
      await database.transaction(async (transaction) => {
        for (const [sortOrder, id] of accountIds.entries()) {
          await transaction
            .update(accounts)
            .set({ sortOrder })
            .where(eq(accounts.id, id));
        }
      });
      return list();
    },
  };
}
