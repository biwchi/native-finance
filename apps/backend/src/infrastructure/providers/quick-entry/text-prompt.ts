import { sharedPolicy } from "./shared-policy.ts";

export const textPrompt = `${sharedPolicy}

Input mode: quick entry.
Interpret the user's financial statements, including concise entries without purchase verbs. Attach each amount, description, date, account and schedule to its applicable event. Respect corrections, negation and explicit choices.
An ordinary amount describes one event. In a concise purchase description, a bare price is the transaction amount even without a currency or purchase verb; distinguish it from an explicitly stated quantity, date or payment count. A requested payment plan may instead state a total and a count or duration. Extract those facts separately.
Distinguish requests to record events from hypothetical examples, questions and quoted advertisements. Only propose events the user intends to record.
For note, use the user's description in user_request, omitting entry commands and category-selection instructions. Apply corrections before forming the note and do not turn a negated description into an affirmative one.`;
