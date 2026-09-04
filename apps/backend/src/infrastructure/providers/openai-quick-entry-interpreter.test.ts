import { describe, expect, it } from "bun:test";

import type { Account } from "../../domain/accounts/account.ts";
import type { Category } from "../../domain/categories/category.ts";
import { createOpenAIQuickEntryInterpreter } from "./openai-quick-entry-interpreter.ts";

describe("createOpenAIQuickEntryInterpreter", () => {
  it("uses GPT-5 nano structured output with the supplied account and category context", async () => {
    let requestBody: Record<string, unknown> = {};
    const fetcher = (async (_input: string | URL | Request, init?: RequestInit) => {
      requestBody = JSON.parse(String(init?.body));
      return new Response(JSON.stringify({
        output: [{
          content: [{
            type: "output_text",
            text: JSON.stringify({ transactions: [], unparsedText: ["nothing"] }),
          }],
        }],
      }), { status: 200 });
    }) as typeof fetch;
    const interpreter = createOpenAIQuickEntryInterpreter({
      apiKey: "test-key",
      fetcher,
    });
    const account = makeAccount();
    const categories = [makeCategory("Food", "expense"), makeCategory("Salary", "income")];

    const result = await interpreter.interpret({
      text: "coffee 4",
      referenceNow: "2026-09-04T12:00:00.000Z",
      timeZone: "Asia/Almaty",
      locale: "en_KZ",
      defaultAccountId: account.id,
      accounts: [account],
      categories,
    });

    expect(result.unparsedText).toEqual(["nothing"]);
    expect(requestBody.model).toBe("gpt-5-nano");
    expect(requestBody.store).toBe(false);
    expect(requestBody.reasoning).toEqual({ effort: "low" });
    expect(String(requestBody.instructions)).toContain(
      "If any temporal expression is present, occurredAt must not be null.",
    );
    expect(String(requestBody.instructions)).toContain(
      "passenger tickets to a destination",
    );
    const context = JSON.parse(String(requestBody.input));
    expect(context.reference_now_utc).toBe("2026-09-04T12:00:00.000Z");
    expect(context.reference_now_local).toBe("2026-09-04T17:00:00+05:00");
    expect(context.accounts).toHaveLength(1);
    expect(context.categories.map((category: { kind: string }) => category.kind)).toEqual([
      "expense",
      "income",
    ]);
  });
});

const date = new Date("2026-09-04T12:00:00.000Z");

function makeAccount(): Account {
  return {
    id: crypto.randomUUID(),
    name: "Kaspi",
    type: "checking",
    currency: "KZT",
    icon: "card",
    iconColor: "red",
    sortOrder: 0,
    createdAt: date,
    updatedAt: date,
  };
}

function makeCategory(name: string, kind: Category["kind"]): Category {
  return {
    id: crypto.randomUUID(),
    systemKey: null,
    name,
    kind,
    parentId: null,
    icon: null,
    color: null,
    isSystem: false,
    examples: [],
    sortOrder: 0,
    createdAt: date,
    updatedAt: date,
  };
}
