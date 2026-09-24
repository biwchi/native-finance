import { t } from "elysia";
import { quickEntryDocumentBase64Limit, quickEntryDocumentTypes } from "../../../application/quick-entry/quick-entry-document.ts";
import { accountBodySchema } from "./account.http-schema.ts";
import { categoryColorSchema } from "./category.http-schema.ts";
import { transactionKindSchema } from "./finance.http-schema.ts";

export const quickEntryBodySchema = t.Object({
  text: t.String({ maxLength: 20_000 }),
  document: t.Optional(t.Object({
    filename: t.String({ minLength: 1, maxLength: 255, pattern: "^[^/\\\\\\u0000-\\u001f]+\\.(?:[pP][dD][fF]|[cC][sS][vV]|[tT][sS][vV]|[xX][lL][sS][xX]?)$" }),
    mediaType: t.Union(Object.values(quickEntryDocumentTypes).map((type) => t.Literal(type))),
    data: t.String({ minLength: 4, maxLength: quickEntryDocumentBase64Limit, pattern: "^[A-Za-z0-9+/]+={0,2}$" }),
  })),
  // The client normalizes camera and library images to JPEG, at most 4 MB.
  photo: t.Optional(t.String({
    maxLength: 5_592_431,
    pattern: "^data:image/jpeg;base64,(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$",
    minLength: 27,
  })),
  defaultAccountId: t.String({ format: "uuid" }),
  locale: t.String({ minLength: 2, maxLength: 100 }),
  timeZone: t.String({ minLength: 1, maxLength: 100 }),
  // This is parser context only. Finance writes still pass through validated mutations.
  context: t.Optional(t.Object({
    accounts: t.Array(t.Object({ id: t.String({ format: "uuid" }), ...accountBodySchema.properties }), { maxItems: 1000 }),
    categories: t.Array(t.Object({
      id: t.String({ format: "uuid" }), name: t.String({ minLength: 1, maxLength: 80 }), kind: transactionKindSchema,
      parentId: t.Optional(t.Nullable(t.String({ format: "uuid" }))),
      icon: t.Optional(t.Nullable(t.String({ maxLength: 80 }))), color: t.Optional(t.Nullable(categoryColorSchema)),
      examples: t.Optional(t.Array(t.String({ maxLength: 200 }), { maxItems: 100 })),
    }), { maxItems: 5000 }),
  })),
});
