import { describe, expect, it } from "bun:test";

import { createCategory, type Category } from "./category.ts";

describe("createCategory", () => {
  it("normalizes a category and applies defaults", () => {
    const result = createCategory({
      name: "  Restaurants  ",
      kind: "expense",
    }, { parent: null });

    expect(result).toEqual({
      ok: true,
      value: {
        name: "Restaurants",
        kind: "expense",
        parentId: null,
        icon: "tag.fill",
        color: "gray",
      },
    });
  });

  it("rejects a child whose kind differs from its parent", () => {
    const result = createCategory({
      name: "Consulting",
      kind: "income",
      parentId: "parent",
    }, { parent: category("parent", "expense") });

    expect(result).toEqual({
      ok: false,
      error: {
        code: "category_kind_mismatch",
        message: "Subcategory type must match its parent",
      },
    });
  });
});

function category(id: string, kind: Category["kind"]): Category {
  return {
    id,
    systemKey: null,
    name: id,
    kind,
    parentId: null,
    icon: null,
    color: null,
    isSystem: false,
    examples: [],
    sortOrder: 0,
    createdAt: new Date(0),
    updatedAt: new Date(0),
  };
}
