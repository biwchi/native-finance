// Live, opt-in regression using the supplied product screenshot. No finance writes.
// Run from apps/backend: bun run eval:scan
import { config } from "../config.ts";
import { createOpenAIQuickEntryInterpreter } from "../infrastructure/providers/openai-quick-entry-interpreter.ts";
import type { QuickEntryInterpreterInput } from "../application/quick-entry/quick-entry-interpreter.ts";

const date = new Date("2026-09-11T12:00:00Z");
const account = { id: "11111111-1111-4111-8111-111111111111", name: "Ruble account", initialBalance: "0",
  currency: "RUB", icon: "bank", iconColor: "green" as const, sortOrder: 0, createdAt: date, updatedAt: date };
const alternativeAccount = { ...account, id: "22222222-2222-4222-8222-222222222222", name: "Kaspi", currency: "KZT" };
const category = { id: "33333333-3333-4333-8333-333333333333", name: "Entertainment", kind: "expense" as const,
  parentId: null, icon: null, color: null, isSystem: false, systemKey: null, examples: ["Video games"],
  sortOrder: 0, createdAt: date, updatedAt: date };
const image = await Bun.file(new URL("../../../../fixtures/scan-entry/product-financing.png", import.meta.url)).arrayBuffer();
const input: QuickEntryInterpreterInput = {
  text: "Recognize the purchases in this photo.", photo: `data:image/png;base64,${Buffer.from(image).toString("base64")}`,
  referenceNow: date.toISOString(), timeZone: "Asia/Almaty", locale: "ru_RU", defaultAccountId: account.id,
  accounts: [account, alternativeAccount], categories: [category],
};

const interpreter = createOpenAIQuickEntryInterpreter({ apiKey: config.openAIApiKey,
  model: config.openAIModel, baseUrl: config.openAIBaseUrl });

let failures = 0;
for (const scenario of [
  { name: "default purchase", text: input.text, amount: "27756", recurring: false },
  { name: "explicit one-time purchase", text: "Я купил эту игру за полную стоимость, без рассрочки.", amount: "27756", recurring: false },
  { name: "explicit installments", text: "Я купил эту игру в рассрочку на 12 месяцев. Создай ежемесячные платежи.", amount: "2313", recurring: true },
]) {
  const result = await interpreter.interpret({ ...input, text: scenario.text });
  const draft = result.transactions[0];
  const passed = result.transactions.length === 1 && draft?.amount === scenario.amount && draft.currency === "KZT"
    && (draft.accountId === account.id || draft.accountId === null) && draft.kind === "expense"
    && (scenario.recurring ? draft.recurrence?.frequency === "monthly" && draft.recurrence.endAt !== null : draft.recurrence === null);
  console.log(JSON.stringify({ scenario: scenario.name, passed, amount: draft?.amount, currency: draft?.currency,
    accountId: draft?.accountId, recurrence: draft?.recurrence }));
  if (!passed) failures++;
}
if (failures) throw new Error(`${failures} scan scenarios failed`);
