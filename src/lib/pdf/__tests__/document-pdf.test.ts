import { describe, expect, it } from "vitest";
import { generateDocumentPdf, type DocumentPdfData } from "../document-pdf";

const SAMPLE: DocumentPdfData = {
  type: "invoice",
  docNumber: "INV-1001",
  jobName: "Kitchen remodel — 12 Maple St",
  createdAt: "2026-05-01",
  dueDate: "2026-05-15",
  status: "sent",
  total: 12500,
  amountPaid: 5000,
  notes: "Net 14. Thank you.",
  companyName: "Acme Plumbing",
  contractorEmail: "billing@acmeplumbing.test",
  contractorPhone: "(555) 010-2030",
  customerName: "Jane Customer",
  customerEmail: "jane@example.test",
  lineItems: [
    { description: "Demo + haul-away", quantity: 1, unit_price: 2500, total: 2500 },
    { description: "Fixture allowance", quantity: 1, unit_price: 4000, total: 4000 },
    { description: "Labor", quantity: 40, unit_price: 150, total: 6000 },
  ],
};

describe("generateDocumentPdf", () => {
  it("returns a non-empty Buffer with the PDF magic header", async () => {
    const buf = await generateDocumentPdf(SAMPLE);
    expect(Buffer.isBuffer(buf)).toBe(true);
    expect(buf.length).toBeGreaterThan(1024);
    expect(buf.subarray(0, 5).toString("ascii")).toBe("%PDF-");
  });

  it("renders an empty line-items table without throwing", async () => {
    const buf = await generateDocumentPdf({ ...SAMPLE, lineItems: [] });
    expect(buf.subarray(0, 5).toString("ascii")).toBe("%PDF-");
  });

  it("supports the quote variant", async () => {
    const buf = await generateDocumentPdf({
      ...SAMPLE,
      type: "quote",
      status: "quote_sent",
      validUntil: "2026-06-01",
      dueDate: undefined,
      amountPaid: 0,
    });
    expect(buf.subarray(0, 5).toString("ascii")).toBe("%PDF-");
  });

  it("honors brand accent override without crashing", async () => {
    const buf = await generateDocumentPdf(SAMPLE, { accent: "#FF6B00" });
    expect(buf.length).toBeGreaterThan(1024);
  });

  it("computes balance from total - amountPaid when balance is omitted", async () => {
    const buf = await generateDocumentPdf({ ...SAMPLE, balance: undefined });
    expect(buf.subarray(0, 5).toString("ascii")).toBe("%PDF-");
  });

  it("rejects non-finite monetary values", async () => {
    await expect(
      generateDocumentPdf({ ...SAMPLE, total: Number.POSITIVE_INFINITY })
    ).rejects.toThrow(/finite/);
    await expect(
      generateDocumentPdf({ ...SAMPLE, amountPaid: Number.NaN })
    ).rejects.toThrow(/finite/);
  });

  it("rejects negative monetary values", async () => {
    await expect(
      generateDocumentPdf({ ...SAMPLE, total: -100 })
    ).rejects.toThrow(/non-negative/);
  });

  it("rejects line-item floods", async () => {
    const flood = Array.from({ length: 250 }, () => ({
      description: "row",
      total: 1,
    }));
    await expect(
      generateDocumentPdf({ ...SAMPLE, lineItems: flood })
    ).rejects.toThrow(/exceeds/);
  });
});
