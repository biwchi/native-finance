import type { Account } from "../accounts/account.ts";
import type { Category } from "../categories/category.ts";
import { error, ok, type Result } from "../shared/result.ts";
import {
  createBudgetCategoryAssignment,
  type BudgetCategoryAssignment,
  type BudgetCategoryAssignmentInput,
} from "./budget-category-assignment.ts";
import {
  createBudgetGroup,
  type BudgetGroup,
  type BudgetGroupInput,
} from "./budget-group.ts";

export type Budget = {
  id: string;
  accountId: string | null;
  month: string;
  currency: string;
  monthlyLimit: string | null;
  groups: BudgetGroup[];
  categoryAssignments: BudgetCategoryAssignment[];
  createdAt: Date;
  updatedAt: Date;
};

export type BudgetInput = {
  month: string;
  accountId?: string | null;
  currency: string;
  monthlyLimit?: string | null;
  groups: BudgetGroupInput[];
  categoryAssignments: BudgetCategoryAssignmentInput[];
};

export type BudgetDraft = Omit<
  Budget,
  "id" | "createdAt" | "updatedAt"
> & { month: string };

export type BudgetValidationError =
  | "account_not_found"
  | "currency_mismatch"
  | "empty_group_name"
  | "duplicate_group_id"
  | "duplicate_group_name"
  | "duplicate_category_assignment"
  | "unknown_group"
  | "missing_standalone_limit"
  | "category_not_found"
  | "income_category";

export function createBudget(
  input: BudgetInput,
  context: { account: Account | null; categories: Category[] },
): Result<BudgetDraft, BudgetValidationError> {
  const accountId = input.accountId ?? null;
  const currency = input.currency.toUpperCase();
  if (accountId && !context.account) {
    return error("account_not_found", "Account not found");
  }
  if (context.account && context.account.currency !== currency) {
    return error(
      "currency_mismatch",
      "Budget currency must match the account currency",
    );
  }

  const groups: BudgetGroup[] = [];
  for (const [sortOrder, inputGroup] of input.groups.entries()) {
    const group = createBudgetGroup(inputGroup, sortOrder);
    if (!group.ok) return group;
    groups.push(group.value);
  }
  if (new Set(groups.map((group) => group.id)).size !== groups.length) {
    return error("duplicate_group_id", "Budget group IDs must be unique");
  }
  if (
    new Set(groups.map((group) => group.name.toLocaleLowerCase("en-US"))).size !==
      groups.length
  ) {
    return error("duplicate_group_name", "Budget group names must be unique");
  }

  const groupIds = new Set(groups.map((group) => group.id));
  const categoryAssignments: BudgetCategoryAssignment[] = [];
  for (const inputAssignment of input.categoryAssignments) {
    const assignment = createBudgetCategoryAssignment(inputAssignment, groupIds);
    if (!assignment.ok) return assignment;
    categoryAssignments.push(assignment.value);
  }
  const categoryIds = categoryAssignments.map((assignment) => assignment.categoryId);
  if (new Set(categoryIds).size !== categoryIds.length) {
    return error(
      "duplicate_category_assignment",
      "Each category can only appear once in a monthly budget",
    );
  }

  const categoriesById = new Map(
    context.categories.map((category) => [category.id, category]),
  );
  if (categoryIds.some((id) => !categoriesById.has(id))) {
    return error("category_not_found", "Category not found");
  }
  if (categoryIds.some((id) => categoriesById.get(id)?.kind !== "expense")) {
    return error(
      "income_category",
      "Only expense categories can have spending budgets",
    );
  }

  return ok({
    accountId,
    month: `${input.month}-01`,
    currency,
    monthlyLimit: input.monthlyLimit ?? null,
    groups,
    categoryAssignments,
  });
}

export function hasBudgetValues(budget: BudgetDraft): boolean {
  return Boolean(
    budget.monthlyLimit ||
    budget.groups.length ||
    budget.categoryAssignments.length
  );
}
