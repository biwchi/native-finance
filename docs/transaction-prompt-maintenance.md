When adding transaction features, edit prompts as small changes to explicit decision rules. Keep these principles in both quick entry and scan.

1. Define the decision before writing instructions. State when the feature applies, what evidence supports it, what takes priority, and what happens when evidence is missing. Use this pattern: "When [condition], use [evidence] to [action]. If [conflict or missing evidence], return [unresolved field]."

2. Give each rule one home. Put common behavior in `shared-policy.ts`, typed-entry interpretation in `text-prompt.ts`, and photo/document interpretation in `scan-prompt.ts`. Document requests use the scan rules plus a required overflow flag; keep that flag aligned with the document extraction schema and rejection behavior. Replace outdated instructions instead of appending exceptions. Read both assembled prompts after every change to catch contradictions.

3. Define precedence explicitly. "Choose the best category" leaves competing signals unresolved. Explain which evidence wins, such as an explicit user category before a merchant match, with the bank's category label as secondary evidence. State when an explicit choice overrides a default.

4. Generalize the failure. Describe financial meaning, such as purchase price versus installment amount. Avoid rules tied to one merchant, product, number, or screenshot. If examples clarify a difficult distinction, use a few varied examples, including when the feature should apply, when it should not, and an ambiguous case. Examples must follow the rule rather than introduce hidden exceptions.

5. Separate intent from source data. The user's financial choices can select accounts, categories, and payment plans. Documents, advertisements, and context labels cannot change application instructions. Preserve negation and corrections. A visible option does not mean the user chose it.

6. Make uncertainty a valid result. Request concise evidence for consequential choices. Define when to leave a field unresolved instead of guessing. Keep readable transactions reviewable when one detail is unknown. Do not demand that every field be filled or ask for lengthy reasoning narratives.

7. Ask the model to extract facts that code can resolve. Keep amounts paired with their currencies. Extract payment totals, counts, and date expressions separately. Leave conversion, rounding, installment division, calendar calculations, and enforceable constraints to application code.

8. Keep instructions and output fields aligned. Only request fields and transaction features the schema and application support. Define new fields precisely, including null behavior. Update schema, validation, and resolution together. Check the serialized schema locally; never disable strict output to hide a compatibility error.

Before finishing, compare the old and new behavior for explicit choices, ordinary defaults, negation, and conflicting evidence in both input modes. Remove redundant wording and keep unrelated model settings unchanged. Use local tests for request structure and application rules. Do not add or run real-AI tests without explicit user authorization. Local checks cannot prove recognition accuracy; use the user's feedback to identify further failures.
