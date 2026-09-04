import { error, ok, type Result } from "../../domain/shared/result.ts";
import type { CategoryRepository } from "./category.repository.ts";

export async function deleteCategory(
  id: string,
  dependencies: { categories: CategoryRepository },
): Promise<Result<{ id: string }, "category_not_found" | "system_category">> {
  const category = await dependencies.categories.findById(id);
  if (!category) return error("category_not_found", "Category not found");
  if (category.isSystem) {
    return error("system_category", "Built-in categories cannot be deleted");
  }
  await dependencies.categories.delete(id);
  return ok({ id });
}
