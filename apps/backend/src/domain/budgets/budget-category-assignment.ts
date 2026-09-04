import { error, ok, type Result } from "../shared/result.ts";

export type BudgetCategoryAssignmentInput = {
  categoryId: string;
  groupId?: string | null;
  limit?: string | null;
};

export type BudgetCategoryAssignment = {
  categoryId: string;
  groupId: string | null;
  limit: string | null;
};

export function createBudgetCategoryAssignment(
  input: BudgetCategoryAssignmentInput,
  groupIds: ReadonlySet<string>,
): Result<
  BudgetCategoryAssignment,
  "unknown_group" | "missing_standalone_limit"
> {
  const assignment = {
    categoryId: input.categoryId,
    groupId: input.groupId ?? null,
    limit: input.limit ?? null,
  };
  if (assignment.groupId && !groupIds.has(assignment.groupId)) {
    return error("unknown_group", "Category assignment references an unknown group");
  }
  if (!assignment.groupId && !assignment.limit) {
    return error(
      "missing_standalone_limit",
      "Standalone category budgets require a limit",
    );
  }
  return ok(assignment);
}
