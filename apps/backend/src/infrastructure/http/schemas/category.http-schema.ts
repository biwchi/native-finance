import { t } from "elysia";

import { transactionKindSchema } from "./finance.http-schema.ts";

const categoryColorSchema = t.Union([
  t.Literal("red"),
  t.Literal("coral"),
  t.Literal("orange"),
  t.Literal("amber"),
  t.Literal("yellow"),
  t.Literal("lime"),
  t.Literal("green"),
  t.Literal("mint"),
  t.Literal("teal"),
  t.Literal("turquoise"),
  t.Literal("cyan"),
  t.Literal("sky"),
  t.Literal("blue"),
  t.Literal("navy"),
  t.Literal("indigo"),
  t.Literal("violet"),
  t.Literal("purple"),
  t.Literal("lavender"),
  t.Literal("pink"),
  t.Literal("rose"),
  t.Literal("brown"),
  t.Literal("slate"),
  t.Literal("gray"),
]);

export const categoryQuerySchema = t.Object({
  kind: t.Optional(transactionKindSchema),
});

export const createCategoryBodySchema = t.Object({
  name: t.String({ minLength: 1, maxLength: 80 }),
  kind: transactionKindSchema,
  parentId: t.Optional(t.String({ format: "uuid" })),
  icon: t.Optional(t.String({ minLength: 1, maxLength: 80 })),
  color: t.Optional(categoryColorSchema),
});

export const updateCategoryBodySchema = t.Object({
  name: t.String({ minLength: 1, maxLength: 80 }),
  parentId: t.Optional(t.Union([t.String({ format: "uuid" }), t.Null()])),
  icon: t.Optional(t.String({ minLength: 1, maxLength: 80 })),
  color: t.Optional(categoryColorSchema),
});

export const categoryIdParamsSchema = t.Object({
  id: t.String({ format: "uuid" }),
});

export const categorySuggestionBodySchema = t.Object({
  description: t.String({ minLength: 1, maxLength: 2_000 }),
  kind: transactionKindSchema,
});
