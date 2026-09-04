import { describe, expect, it } from "bun:test";

import type { Account } from "../../domain/accounts/account.ts";
import type { Category } from "../../domain/categories/category.ts";
import { createOpenAIQuickEntryInterpreter } from "./openai-quick-entry-interpreter.ts";

describe("createOpenAIQuickEntryInterpreter", () => {
  it("uses GPT-5.6 Luna at low reasoning with the supplied account and category context", async () => {
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
    expect(requestBody.model).toBe("gpt-5.6-luna");
    expect(requestBody.store).toBe(false);
    expect(requestBody.reasoning).toEqual({ effort: "low" });
    expect(String(requestBody.instructions)).toContain(
      "If any temporal expression is present, occurredAt must not be null.",
    );
    expect(String(requestBody.instructions)).toContain(
      "passenger tickets to a destination",
    );
    expect(String(requestBody.instructions)).toContain(
      '"coffee 4.5" maps to Food & Drink with note "coffee"',
    );
    expect(String(requestBody.instructions)).toContain(
      '"Купил продукты 10000" maps to Groceries with note null',
    );
    expect(String(requestBody.instructions)).toContain(
      "A transfer is only a movement between two different accounts from the supplied accounts list",
    );
    expect(String(requestBody.instructions)).toContain(
      "the other side resolves to a different explicitly named supplied account or default_account_id",
    );
    expect(String(requestBody.instructions)).toContain(
      '"transfer" or Russian "перевод"',
    );
    expect(String(requestBody.instructions)).toContain(
      'a misspelled or mixed-script variant such as "Перевод Caше 20 000"',
    );
    expect(String(requestBody.instructions)).toContain(
      "is an expense with accountId default_account_id, destinationAccountId null",
    );
    expect(String(requestBody.instructions)).toContain(
      "Amount is the money moved by one transaction occurrence, not the total value of a recurring plan",
    );
    expect(String(requestBody.instructions)).toContain(
      "divide the total by the number of occurrences and return that quotient as amount",
    );
    expect(String(requestBody.instructions)).toContain(
      '"Купил новый ноутбук рассрочку за 1 500 000 на два года"',
    );
    expect(String(requestBody.instructions)).toContain(
      'amount "62500"',
    );
    expect(String(requestBody.instructions)).toContain(
      '"endAt":"2028-08-05T00:13:00+05:00"',
    );
    expect(String(requestBody.instructions)).toContain(
      'not 24 occurrences of "1500000"',
    );
    expect(JSON.stringify(requestBody.text)).toContain(
      "For installments, use the per-payment amount, not the total plan price.",
    );
    expect(String(requestBody.instructions)).toContain(
      "endAt is non-null whenever it states a duration, final date, or occurrence count",
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
