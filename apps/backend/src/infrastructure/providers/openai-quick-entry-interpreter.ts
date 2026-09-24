import { TypeCompiler } from "@sinclair/typebox/compiler";
import type { QuickEntryInterpreter } from "../../application/quick-entry/quick-entry-interpreter.ts";
import { resolveQuickEntryExtraction } from "../../application/quick-entry/resolve-quick-entry-extraction.ts";
import { extractionSchema } from "./quick-entry/extraction-schema.ts";
import { promptContext } from "./quick-entry/prompt-context.ts";
import { documentScanPrompt, scanPrompt } from "./quick-entry/scan-prompt.ts";
import { textPrompt } from "./quick-entry/text-prompt.ts";
import { quickEntryDocumentDraftLimit } from "../../application/quick-entry/quick-entry-interpreter.ts";

export function createOpenAIQuickEntryInterpreter(options: {
  apiKey: string | undefined;
  model?: string;
  baseUrl?: string;
  fetcher?: typeof fetch;
}): QuickEntryInterpreter {
  const model = options.model ?? "gpt-5.6-luna";
  const baseUrl = options.baseUrl ?? "https://api.openai.com/v1";
  const fetcher = options.fetcher ?? fetch;

  return {
    async interpret(input) {
      if (!options.apiKey) throw new Error("OPENAI_API_KEY is not configured");
      const schema = extractionSchema(input);
      const validator = TypeCompiler.Compile(schema);
      const context = JSON.stringify(promptContext(input));
      const response = await fetcher(`${baseUrl}/responses`, {
        method: "POST",
        ...(input.document ? { signal: AbortSignal.timeout(170_000) } : {}),
        headers: { Authorization: `Bearer ${options.apiKey}`, "Content-Type": "application/json" },
        body: JSON.stringify({
          model, store: false, reasoning: { effort: "low" },
          max_output_tokens: input.document ? 128_000 : 32_768,
          instructions: input.document ? documentScanPrompt : input.photo ? scanPrompt : textPrompt,
          input: input.photo || input.document ? [{
            role: "user",
            content: [
              { type: "input_text", text: context },
              ...(input.document ? [{ type: "input_file", filename: input.document.filename,
                file_data: `data:${input.document.mediaType};base64,${input.document.data}` }]
                : [{ type: "input_image", image_url: input.photo, detail: "high" }]),
            ],
          }] : context,
          text: { format: { type: "json_schema", name: "transaction_evidence_v3", strict: true, schema } },
        }),
      });
      const payload = await response.json() as OpenAIResponse;
      if (!response.ok) throw new Error(payload.error?.message ?? `OpenAI request failed (${response.status})`);
      if (payload.status === "incomplete") throw new Error("The entry is too large to finish reading. Try fewer transactions at once.");
      const output = responseText(payload);
      if (!output) throw new Error("No transaction data was returned. Try another description, photo, or document.");
      const parsed: unknown = JSON.parse(output);
      if (!validator.Check(parsed)) throw new Error("The transaction response was incomplete or invalid. Please try again.");
      if ("hasMoreTransactions" in parsed && parsed.hasMoreTransactions) {
        throw new Error(`Choose a smaller document with up to ${quickEntryDocumentDraftLimit} transactions. The document could not be read in full.`);
      }
      return resolveQuickEntryExtraction(parsed, input);
    },
  };
}

type OpenAIResponse = {
  status?: string;
  output_text?: string;
  output?: Array<{ content?: Array<{ type?: string; text?: string }> }>;
  error?: { message?: string };
};

function responseText(response: OpenAIResponse): string | null {
  if (response.output_text) return response.output_text;
  const parts = response.output?.flatMap((output) => output.content ?? [])
    .filter((content) => content.type === "output_text" && content.text).map((content) => content.text);
  return parts?.length ? parts.join("") : null;
}
