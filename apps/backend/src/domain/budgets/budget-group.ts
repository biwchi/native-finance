import { error, ok, type Result } from "../shared/result.ts";

export type BudgetGroupInput = {
  id: string;
  name: string;
  limit: string;
};

export type BudgetGroup = BudgetGroupInput & {
  sortOrder: number;
};

export function createBudgetGroup(
  input: BudgetGroupInput,
  sortOrder: number,
): Result<BudgetGroup, "empty_group_name"> {
  const name = input.name.trim();
  return name
    ? ok({ ...input, name, sortOrder })
    : error("empty_group_name", "Budget group names cannot be empty");
}
