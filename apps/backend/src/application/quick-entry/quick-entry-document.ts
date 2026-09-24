export const quickEntryDocumentByteLimit = 10 * 1024 * 1024;
export const quickEntryDocumentBase64Limit = Math.ceil(quickEntryDocumentByteLimit / 3) * 4;

export const quickEntryDocumentTypes = {
  pdf: "application/pdf",
  csv: "text/csv",
  tsv: "text/tsv",
  xls: "application/vnd.ms-excel",
  xlsx: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
} as const;

export type QuickEntryDocument = {
  filename: string;
  mediaType: string;
  data: string;
};

/** Validate the encoded bytes as well as the HTTP envelope before calling AI. */
export function validateQuickEntryDocument(document: QuickEntryDocument): string | null {
  const extension = document.filename.split(".").at(-1)?.toLowerCase();
  const mediaType = quickEntryDocumentTypes[extension as keyof typeof quickEntryDocumentTypes];
  if (!mediaType || mediaType !== document.mediaType || document.filename.length > 255
    || /[/\\\x00-\x1f]/.test(document.filename)) {
    return "Choose a PDF, CSV, TSV, XLS, or XLSX file.";
  }
  if (document.data.length > quickEntryDocumentBase64Limit) return "Choose a file smaller than 10 MB.";
  const data = Buffer.from(document.data, "base64");
  if (!data.length || data.toString("base64") !== document.data) return "This document is empty or could not be read.";
  if (data.length > quickEntryDocumentByteLimit) return "Choose a file smaller than 10 MB.";
  if (extension === "pdf" && !data.subarray(0, 1024).includes(Buffer.from("%PDF-"))) {
    return "This PDF could not be opened. Choose another file.";
  }
  if (extension === "xlsx" && !data.subarray(0, 4).equals(Buffer.from([0x50, 0x4b, 0x03, 0x04]))) {
    return "This Excel file could not be opened. Export it as XLSX or CSV and try again.";
  }
  if (extension === "xls" && !data.subarray(0, 8).equals(Buffer.from([0xd0, 0xcf, 0x11, 0xe0, 0xa1, 0xb1, 0x1a, 0xe1]))) {
    return "This Excel file could not be opened. Export it as XLSX or CSV and try again.";
  }
  return null;
}
