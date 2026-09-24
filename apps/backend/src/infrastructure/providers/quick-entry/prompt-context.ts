import { createQuickEntryCalendar } from "../../../application/quick-entry/quick-entry-calendar.ts";
import type { QuickEntryInterpreterInput } from "../../../application/quick-entry/quick-entry-interpreter.ts";

export function promptContext(input: QuickEntryInterpreterInput) {
  const byId = new Map(input.categories.map((category) => [category.id.toLowerCase(), category]));
  return {
    policy_version: "transactions-v4",
    input_mode: input.photo || input.document ? "scan" : "quick_entry",
    user_request: input.text,
    reference_instant: input.referenceNow,
    reference_local: createQuickEntryCalendar(input.referenceNow, input.timeZone).localReference(),
    time_zone: input.timeZone,
    locale: input.locale,
    selected_account_id: input.defaultAccountId,
    accounts: input.accounts.map(({ id, name, currency }) => ({ id, name, currency })),
    categories: input.categories.filter((category) => category.kind !== "debt").map((category) => {
      const path: string[] = [];
      const visited = new Set<string>();
      let current: typeof category | undefined = category;
      while (current && !visited.has(current.id.toLowerCase())) {
        visited.add(current.id.toLowerCase()); path.unshift(current.name);
        current = current.parentId ? byId.get(current.parentId.toLowerCase()) : undefined;
      }
      return { id: category.id, name: category.name, kind: category.kind, parent_id: category.parentId, path, examples: category.examples };
    }),
  };
}
