import { and, asc, eq, inArray, isNull } from "drizzle-orm";
import { Elysia, t } from "elysia";

import { db } from "../db/client.ts";
import {
  accounts,
  budgetCategoryAssignments,
  budgetGroups,
  budgetPlans,
  categories,
} from "../db/schema.ts";

const monthPattern = "^\\d{4}-(?:0[1-9]|1[0-2])$";
const amountPattern =
  "^(?=.{1,20}$)(?!0+(?:\\.0{1,4})?$)(?:0|[1-9]\\d{0,14})(?:\\.\\d{1,4})?$";

const budgetQuery = t.Object({
  month: t.String({ pattern: monthPattern }),
  accountId: t.Optional(t.String({ format: "uuid" })),
});

const budgetBody = t.Object({
  month: t.String({ pattern: monthPattern }),
  accountId: t.Optional(t.Nullable(t.String({ format: "uuid" }))),
  currency: t.String({ pattern: "^[A-Za-z]{3}$" }),
  monthlyLimit: t.Optional(t.Nullable(t.String({ pattern: amountPattern }))),
  groups: t.Array(
    t.Object({
      id: t.String({ format: "uuid" }),
      name: t.String({ minLength: 1, maxLength: 80 }),
      limit: t.String({ pattern: amountPattern }),
    }),
    { maxItems: 100 },
  ),
  categoryAssignments: t.Array(
    t.Object({
      categoryId: t.String({ format: "uuid" }),
      groupId: t.Optional(t.Nullable(t.String({ format: "uuid" }))),
      limit: t.Optional(t.Nullable(t.String({ pattern: amountPattern }))),
    }),
    { maxItems: 500 },
  ),
});

export const budgetsRoutes = new Elysia({ prefix: "/budgets" })
  .get(
    "/monthly",
    async ({ query }) => {
      const plan = await findPlan(monthDate(query.month), query.accountId ?? null);
      return plan ? loadBudget(plan.id) : null;
    },
    { query: budgetQuery },
  )
  .put(
    "/monthly",
    async ({ body, set }) => {
      const prepared = await prepareBudget(body);
      if ("error" in prepared) {
        set.status = prepared.status;
        return { message: prepared.error };
      }

      const existing = await findPlan(prepared.month, prepared.accountId);
      if (!prepared.hasBudget) {
        if (existing) {
          await db.delete(budgetPlans).where(eq(budgetPlans.id, existing.id));
        }
        return null;
      }

      const planId = await db.transaction(async (transaction) => {
        const [plan] = existing
          ? await transaction
              .update(budgetPlans)
              .set({
                currency: prepared.currency,
                monthlyLimit: prepared.monthlyLimit,
                updatedAt: new Date(),
              })
              .where(eq(budgetPlans.id, existing.id))
              .returning({ id: budgetPlans.id })
          : await transaction
              .insert(budgetPlans)
              .values({
                accountId: prepared.accountId,
                month: prepared.month,
                currency: prepared.currency,
                monthlyLimit: prepared.monthlyLimit,
              })
              .returning({ id: budgetPlans.id });

        if (!plan) {
          throw new Error("Budget plan write did not return a row");
        }

        await transaction
          .delete(budgetCategoryAssignments)
          .where(eq(budgetCategoryAssignments.planId, plan.id));
        await transaction
          .delete(budgetGroups)
          .where(eq(budgetGroups.planId, plan.id));

        if (prepared.groups.length > 0) {
          await transaction.insert(budgetGroups).values(
            prepared.groups.map((group, index) => ({
              id: group.id,
              planId: plan.id,
              name: group.name,
              limit: group.limit,
              sortOrder: index,
            })),
          );
        }

        if (prepared.categoryAssignments.length > 0) {
          await transaction.insert(budgetCategoryAssignments).values(
            prepared.categoryAssignments.map((assignment) => ({
              planId: plan.id,
              categoryId: assignment.categoryId,
              groupId: assignment.groupId,
              limit: assignment.limit,
            })),
          );
        }

        return plan.id;
      });

      return loadBudget(planId);
    },
    { body: budgetBody },
  );

async function prepareBudget(body: typeof budgetBody.static) {
  const accountId = body.accountId ?? null;
  const currency = body.currency.toUpperCase();

  if (accountId) {
    const [account] = await db
      .select({ currency: accounts.currency })
      .from(accounts)
      .where(eq(accounts.id, accountId))
      .limit(1);

    if (!account) {
      return { error: "Account not found", status: 404 as const };
    }
    if (account.currency !== currency) {
      return {
        error: "Budget currency must match the account currency",
        status: 400 as const,
      };
    }
  }

  const groups = body.groups.map((group) => ({
    ...group,
    name: group.name.trim(),
  }));
  if (groups.some((group) => !group.name)) {
    return { error: "Budget group names cannot be empty", status: 400 as const };
  }
  if (new Set(groups.map((group) => group.id)).size !== groups.length) {
    return { error: "Budget group IDs must be unique", status: 400 as const };
  }
  if (new Set(groups.map((group) => group.name.toLocaleLowerCase("en-US"))).size !== groups.length) {
    return { error: "Budget group names must be unique", status: 400 as const };
  }

  const groupIDs = new Set(groups.map((group) => group.id));
  const assignments = body.categoryAssignments.map((assignment) => ({
    categoryId: assignment.categoryId,
    groupId: assignment.groupId ?? null,
    limit: assignment.limit ?? null,
  }));
  if (new Set(assignments.map((assignment) => assignment.categoryId)).size !== assignments.length) {
    return {
      error: "Each category can only appear once in a monthly budget",
      status: 400 as const,
    };
  }
  if (assignments.some((assignment) => assignment.groupId && !groupIDs.has(assignment.groupId))) {
    return { error: "Category assignment references an unknown group", status: 400 as const };
  }
  if (assignments.some((assignment) => !assignment.groupId && !assignment.limit)) {
    return {
      error: "Standalone category budgets require a limit",
      status: 400 as const,
    };
  }

  const categoryIDs = assignments.map((assignment) => assignment.categoryId);
  if (categoryIDs.length > 0) {
    const selectedCategories = await db
      .select({ id: categories.id, kind: categories.kind })
      .from(categories)
      .where(inArray(categories.id, categoryIDs));

    if (selectedCategories.length !== categoryIDs.length) {
      return { error: "Category not found", status: 404 as const };
    }
    if (selectedCategories.some((category) => category.kind !== "expense")) {
      return {
        error: "Only expense categories can have spending budgets",
        status: 400 as const,
      };
    }
  }

  return {
    accountId,
    month: monthDate(body.month),
    currency,
    monthlyLimit: body.monthlyLimit ?? null,
    groups,
    categoryAssignments: assignments,
    hasBudget: Boolean(body.monthlyLimit || groups.length || assignments.length),
  };
}

function monthDate(month: string): string {
  return `${month}-01`;
}

async function findPlan(month: string, accountId: string | null) {
  const [plan] = await db
    .select()
    .from(budgetPlans)
    .where(
      and(
        eq(budgetPlans.month, month),
        accountId ? eq(budgetPlans.accountId, accountId) : isNull(budgetPlans.accountId),
      ),
    )
    .limit(1);
  return plan;
}

async function loadBudget(planId: string) {
  const [plan] = await db
    .select()
    .from(budgetPlans)
    .where(eq(budgetPlans.id, planId))
    .limit(1);

  if (!plan) {
    return null;
  }

  const [groups, categoryAssignments] = await Promise.all([
    db
      .select({
        id: budgetGroups.id,
        name: budgetGroups.name,
        limit: budgetGroups.limit,
        sortOrder: budgetGroups.sortOrder,
      })
      .from(budgetGroups)
      .where(eq(budgetGroups.planId, plan.id))
      .orderBy(asc(budgetGroups.sortOrder), asc(budgetGroups.name)),
    db
      .select({
        categoryId: budgetCategoryAssignments.categoryId,
        groupId: budgetCategoryAssignments.groupId,
        limit: budgetCategoryAssignments.limit,
      })
      .from(budgetCategoryAssignments)
      .where(eq(budgetCategoryAssignments.planId, plan.id)),
  ]);

  return {
    id: plan.id,
    accountId: plan.accountId,
    month: plan.month.slice(0, 7),
    currency: plan.currency,
    monthlyLimit: plan.monthlyLimit,
    groups,
    categoryAssignments,
    createdAt: plan.createdAt,
    updatedAt: plan.updatedAt,
  };
}
