import { describe, expect, it } from "bun:test";
import { quickEntryDocumentByteLimit, validateQuickEntryDocument } from "./quick-entry-document.ts";

describe("document byte validation", () => {
  const pdf = { filename: "statement.pdf", mediaType: "application/pdf", data: Buffer.from("%PDF-1.7\nfixture").toString("base64") };

  it("accepts a supported nonempty document", () => {
    expect(validateQuickEntryDocument(pdf)).toBeNull();
  });

  it("rejects noncanonical base64, mismatched formats, renamed files and empty content", () => {
    for (const document of [
      { ...pdf, data: "" }, { ...pdf, data: "YQ" }, { ...pdf, data: "YR==" },
      { ...pdf, filename: "statement.csv" }, { ...pdf, filename: "../../statement.pdf" },
      { ...pdf, data: Buffer.from("not a PDF").toString("base64") },
      { ...pdf, filename: "statement.xls", mediaType: "application/vnd.ms-excel" },
      { ...pdf, filename: "statement.xlsx", mediaType: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" },
    ]) expect(validateQuickEntryDocument(document)).not.toBeNull();
  });

  it("checks decoded size even when the oversized file fits the base64 character limit", () => {
    const data = Buffer.alloc(quickEntryDocumentByteLimit, 32);
    data.write("%PDF-1.7");
    expect(validateQuickEntryDocument({ ...pdf, data: data.toString("base64") })).toBeNull();
    expect(validateQuickEntryDocument({ ...pdf, data: Buffer.concat([data, Buffer.from(" ")]).toString("base64") }))
      .toContain("10 MB");
  });
});
