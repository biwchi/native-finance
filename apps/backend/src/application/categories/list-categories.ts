import type { TransactionKind } from "../../domain/categories/category.ts";
import type { CategoryRepository } from "./category.repository.ts";

export function listCategories(
  input: { kind?: TransactionKind },
  dependencies: { categories: CategoryRepository },
) {
  return dependencies.categories.list(input.kind);
}
