import { and, asc, desc, eq, sql } from "drizzle-orm";
import { Elysia, t } from "elysia";

import { db } from "../db/client.ts";
import { categories, transactions } from "../db/schema.ts";
import {
  normalizeTransactionDescription,
  rankHistoryMatches,
  type HistoryMatch,
} from "../services/category-resolution.ts";

export const transactionKindSchema = t.Union([
  t.Literal("expense"),
  t.Literal("income"),
]);

type FuzzyHistoryRow = {
  categoryId: string;
  similarity: number;
  createdAt: Date | string;
};

export const categoriesRoutes = new Elysia({ prefix: "/categories" })
  .get(
    "/",
    ({ query }) => {
      const filters = query.kind
        ? eq(categories.kind, query.kind)
        : undefined;

      return db
        .select()
        .from(categories)
        .where(filters)
        .orderBy(
          asc(categories.kind),
          asc(categories.sortOrder),
          asc(categories.name),
        );
    },
    {
      query: t.Object({
        kind: t.Optional(transactionKindSchema),
      }),
    },
  )
  .post(
    "/",
    async ({ body, set }) => {
      const name = body.name.trim();

      if (!name) {
        set.status = 400;
        return { message: "Category name cannot be empty" };
      }

      const [duplicate] = await db
        .select({ id: categories.id })
        .from(categories)
        .where(
          and(
            eq(categories.kind, body.kind),
            sql`lower(${categories.name}) = ${name.toLocaleLowerCase("en-US")}`,
          ),
        )
        .limit(1);

      if (duplicate) {
        set.status = 409;
        return { message: "A category with this name already exists" };
      }

      try {
        const [category] = await db
          .insert(categories)
          .values({
            name,
            kind: body.kind,
            isSystem: false,
            examples: [],
            sortOrder: 1_000,
          })
          .returning();

        set.status = 201;
        return category;
      } catch (error) {
        if (isUniqueViolation(error)) {
          set.status = 409;
          return { message: "A category with this name already exists" };
        }

        throw error;
      }
    },
    {
      body: t.Object({
        name: t.String({ minLength: 1, maxLength: 80 }),
        kind: transactionKindSchema,
      }),
    },
  )
  .post(
    "/suggest",
    async ({ body }) => {
      const normalizedDescription = normalizeTransactionDescription(
        body.description,
      );

      if (!normalizedDescription) {
        return { suggestions: [] };
      }

      const [exact] = await db
        .select({
          categoryId: transactions.categoryId,
        })
        .from(transactions)
        .where(
          and(
            eq(transactions.kind, body.kind),
            eq(transactions.normalizedDescription, normalizedDescription),
            sql`${transactions.categoryId} is not null`,
          ),
        )
        .orderBy(desc(transactions.createdAt))
        .limit(1);

      if (exact?.categoryId) {
        return {
          suggestions: [
            {
              categoryId: exact.categoryId,
              score: 1,
              source: "exact_history" as const,
            },
          ],
        };
      }

      const result = await db.execute(sql<FuzzyHistoryRow>`
        select
          ${transactions.categoryId} as "categoryId",
          greatest(
            similarity(${transactions.normalizedDescription}, ${normalizedDescription}),
            strict_word_similarity(${normalizedDescription}, ${transactions.normalizedDescription})
          )::double precision as "similarity",
          ${transactions.createdAt} as "createdAt"
        from ${transactions}
        where ${transactions.kind} = ${body.kind}
          and ${transactions.categoryId} is not null
          and ${transactions.normalizedDescription} is not null
          and (
            ${transactions.normalizedDescription} % ${normalizedDescription}
            or ${normalizedDescription} <<% ${transactions.normalizedDescription}
          )
        order by "similarity" desc, ${transactions.createdAt} desc
        limit 50
      `);

      const rows = [...result] as unknown as FuzzyHistoryRow[];
      const matches: HistoryMatch[] = rows.map((row) => ({
        categoryId: row.categoryId,
        similarity: Number(row.similarity),
        createdAt:
          row.createdAt instanceof Date
            ? row.createdAt
            : new Date(row.createdAt),
      }));

      return { suggestions: rankHistoryMatches(matches) };
    },
    {
      body: t.Object({
        description: t.String({ minLength: 1, maxLength: 2_000 }),
        kind: transactionKindSchema,
      }),
    },
  );

function isUniqueViolation(error: unknown): boolean {
  return (
    typeof error === "object" &&
    error !== null &&
    "code" in error &&
    error.code === "23505"
  );
}
