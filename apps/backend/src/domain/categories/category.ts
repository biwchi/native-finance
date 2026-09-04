import { error, ok, type Result } from "../shared/result.ts";

export type TransactionKind = "expense" | "income";

export type Category = {
  id: string;
  systemKey: string | null;
  name: string;
  kind: TransactionKind;
  parentId: string | null;
  icon: string | null;
  color: string | null;
  isSystem: boolean;
  examples: string[];
  sortOrder: number;
  createdAt: Date;
  updatedAt: Date;
};

export type CategorySummary = Omit<
  Category,
  "examples" | "sortOrder" | "createdAt" | "updatedAt"
>;

export type CategoryDraft = Pick<
  Category,
  "name" | "kind" | "parentId" | "icon" | "color"
>;

export type CategoryUpdate = Pick<
  Category,
  "name" | "parentId" | "icon" | "color"
>;

export type CategoryValidationError =
  | "empty_category_name"
  | "parent_not_found"
  | "self_parent"
  | "nested_subcategory"
  | "category_kind_mismatch"
  | "category_has_children";

export function createCategory(
  input: {
    name: string;
    kind: TransactionKind;
    parentId?: string;
    icon?: string;
    color?: string;
  },
  context: { parent: Category | null },
): Result<CategoryDraft, CategoryValidationError> {
  const name = input.name.trim();
  if (!name) return error("empty_category_name", "Category name cannot be empty");
  if (input.parentId && !context.parent) {
    return error("parent_not_found", "Parent category not found");
  }
  if (context.parent?.parentId) {
    return error("nested_subcategory", "Subcategories can only be one level deep");
  }
  if (context.parent && context.parent.kind !== input.kind) {
    return error(
      "category_kind_mismatch",
      "Subcategory type must match its parent",
    );
  }

  return ok({
    name,
    kind: input.kind,
    parentId: context.parent?.id ?? null,
    icon: input.icon ?? "tag.fill",
    color: input.color ?? "gray",
  });
}

export function updateCategory(
  input: {
    id: string;
    name: string;
    parentId: string | null;
    icon?: string;
    color?: string;
  },
  context: {
    existing: Category;
    parent: Category | null;
    hasChildren: boolean;
  },
): Result<CategoryUpdate, CategoryValidationError> {
  const name = input.name.trim();
  if (!name) return error("empty_category_name", "Category name cannot be empty");
  if (input.parentId === input.id) {
    return error("self_parent", "A category cannot be its own parent");
  }
  if (input.parentId && !context.parent) {
    return error("parent_not_found", "Parent category not found");
  }
  if (context.parent?.parentId) {
    return error("nested_subcategory", "Subcategories can only be one level deep");
  }
  if (context.parent && context.parent.kind !== context.existing.kind) {
    return error(
      "category_kind_mismatch",
      "Subcategory type must match its parent",
    );
  }
  if (
    input.parentId &&
    input.parentId !== context.existing.parentId &&
    context.hasChildren
  ) {
    return error(
      "category_has_children",
      "Move or delete this category's subcategories first",
    );
  }

  return ok({
    name,
    parentId: input.parentId,
    icon: input.icon ?? context.existing.icon,
    color: input.color ?? context.existing.color,
  });
}
