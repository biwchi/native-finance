import { and, asc, eq, isNull } from "drizzle-orm";

import type {
  BudgetRepository,
} from "../../../application/budgets/budget.repository.ts";
import type { BudgetDraft } from "../../../domain/budgets/budget.ts";
import type { Database } from "../client.ts";
import {
  budgetCategoryAssignments,
  budgetGroups,
  budgetPlans,
} from "../schema/budget.schema.ts";

export function createDrizzleBudgetRepository(database: Database): BudgetRepository {
  async function findPlan(month: string, accountId: string | null) {
    const [plan] = await database
      .select()
      .from(budgetPlans)
      .where(and(
        eq(budgetPlans.month, month),
        accountId ? eq(budgetPlans.accountId, accountId) : isNull(budgetPlans.accountId),
      ))
      .limit(1);
    return plan ?? null;
  }

  async function load(planId: string) {
    const [plan] = await database
      .select()
      .from(budgetPlans)
      .where(eq(budgetPlans.id, planId))
      .limit(1);
    if (!plan) return null;

    const [groups, assignments] = await Promise.all([
      database
        .select({
          id: budgetGroups.id,
          name: budgetGroups.name,
          limit: budgetGroups.limit,
          sortOrder: budgetGroups.sortOrder,
        })
        .from(budgetGroups)
        .where(eq(budgetGroups.planId, planId))
        .orderBy(asc(budgetGroups.sortOrder), asc(budgetGroups.name)),
      database
        .select({
          categoryId: budgetCategoryAssignments.categoryId,
          groupId: budgetCategoryAssignments.groupId,
          limit: budgetCategoryAssignments.limit,
        })
        .from(budgetCategoryAssignments)
        .where(eq(budgetCategoryAssignments.planId, planId)),
    ]);

    return {
      id: plan.id,
      accountId: plan.accountId,
      month: plan.month.slice(0, 7),
      currency: plan.currency,
      monthlyLimit: plan.monthlyLimit,
      groups,
      categoryAssignments: assignments,
      createdAt: plan.createdAt,
      updatedAt: plan.updatedAt,
    };
  }

  return {
    async find(month, accountId) {
      const plan = await findPlan(month, accountId);
      return plan ? load(plan.id) : null;
    },

    async save(snapshot: BudgetDraft) {
      const existing = await findPlan(snapshot.month, snapshot.accountId);
      const planId = await database.transaction(async (transaction) => {
        const [plan] = existing
          ? await transaction
              .update(budgetPlans)
              .set({
                currency: snapshot.currency,
                monthlyLimit: snapshot.monthlyLimit,
                updatedAt: new Date(),
              })
              .where(eq(budgetPlans.id, existing.id))
              .returning({ id: budgetPlans.id })
          : await transaction
              .insert(budgetPlans)
              .values({
                accountId: snapshot.accountId,
                month: snapshot.month,
                currency: snapshot.currency,
                monthlyLimit: snapshot.monthlyLimit,
              })
              .returning({ id: budgetPlans.id });
        if (!plan) throw new Error("Budget plan write did not return a row");

        await transaction
          .delete(budgetCategoryAssignments)
          .where(eq(budgetCategoryAssignments.planId, plan.id));
        await transaction.delete(budgetGroups).where(eq(budgetGroups.planId, plan.id));

        if (snapshot.groups.length > 0) {
          await transaction.insert(budgetGroups).values(snapshot.groups.map((group) => ({
            ...group,
            planId: plan.id,
          })));
        }
        if (snapshot.categoryAssignments.length > 0) {
          await transaction.insert(budgetCategoryAssignments).values(
            snapshot.categoryAssignments.map((assignment) => ({
              ...assignment,
              planId: plan.id,
            })),
          );
        }
        return plan.id;
      });

      const saved = await load(planId);
      if (!saved) throw new Error("Budget plan not found after save");
      return saved;
    },

    async delete(month, accountId) {
      const plan = await findPlan(month, accountId);
      if (plan) await database.delete(budgetPlans).where(eq(budgetPlans.id, plan.id));
    },
  };
}
