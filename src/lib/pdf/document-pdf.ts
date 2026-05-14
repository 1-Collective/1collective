// [CC-FOUNDATION] Branded PDF generator for invoices and quotes.
// Ported from Contractor Command (api-server/src/lib/pdfGenerator.ts).
// Used by Invoicing, Estimating, Change Orders, AIA pay apps, and lien waivers.

import PDFDocument from "pdfkit";

export interface PdfLineItem {
  description?: string;
  quantity?: number;
  unit_price?: number;
  total?: number;
  amount?: number;
}

export type DocumentPdfType = "invoice" | "quote";

export interface DocumentPdfData {
  type: DocumentPdfType;
  docNumber?: string;
  jobName: string;
  createdAt?: string;
  dueDate?: string;
  validUntil?: string;
  status?: string;
  total: number;
  amountPaid?: number;
  balance?: number;
  notes?: string;
  companyName: string;
  contractorEmail?: string;
  contractorPhone?: string;
  contractorAddress?: string;
  customerName: string;
  customerEmail?: string;
  customerPhone?: string;
  lineItems: PdfLineItem[];
}

export interface PdfBrand {
  accent?: string;
  dark?: string;
  gray?: string;
  light?: string;
}

const DEFAULT_BRAND: Required<PdfBrand> = {
  accent: "#0A0A0A",
  dark: "#1A1A1A",
  gray: "#6B7280",
  light: "#F9FAFB",
};
const WHITE = "#FFFFFF";

function fmtDate(d?: string | null): string {
  if (!d) return "—";
  const dt = new Date(d);
  if (isNaN(dt.getTime())) return String(d);
  return dt.toLocaleDateString("en-US", { month: "short", day: "numeric", year: "numeric" });
}

function fmtMoney(n: number): string {
  return "$" + n.toLocaleString("en-US", { minimumFractionDigits: 2, maximumFractionDigits: 2 });
}

const STATUS_LABELS: Record<string, string> = {
  paid: "PAID",
  sent: "SENT",
  overdue: "OVERDUE",
  draft: "DRAFT",
  partial: "PARTIAL PAYMENT",
  cancelled: "CANCELLED",
  won: "APPROVED",
  lost: "DECLINED",
  quote_sent: "AWAITING APPROVAL",
};

const STATUS_COLORS: Record<string, string> = {
  paid: "#10B981",
  overdue: "#EF4444",
  won: "#10B981",
  lost: "#EF4444",
  sent: "#3B82F6",
};

function statusLabel(s?: string): string {
  if (!s) return "—";
  return STATUS_LABELS[s] ?? s.toUpperCase();
}

function assertFiniteMoney(value: number | undefined, field: string): void {
  if (value === undefined) return;
  if (!Number.isFinite(value)) {
    throw new Error(`generateDocumentPdf: ${field} must be a finite number.`);
  }
  if (value < 0) {
    throw new Error(`generateDocumentPdf: ${field} must be non-negative.`);
  }
}

const MAX_LINE_ITEMS = 200;

export async function generateDocumentPdf(
  data: DocumentPdfData,
  brand: PdfBrand = {}
): Promise<Buffer> {
  assertFiniteMoney(data.total, "total");
  assertFiniteMoney(data.amountPaid, "amountPaid");
  assertFiniteMoney(data.balance, "balance");
  if ((data.lineItems?.length ?? 0) > MAX_LINE_ITEMS) {
    throw new Error(
      `generateDocumentPdf: lineItems exceeds ${MAX_LINE_ITEMS} (got ${data.lineItems.length}).`
    );
  }
  for (const [i, item] of (data.lineItems ?? []).entries()) {
    assertFiniteMoney(item.unit_price, `lineItems[${i}].unit_price`);
    assertFiniteMoney(item.total, `lineItems[${i}].total`);
    assertFiniteMoney(item.amount, `lineItems[${i}].amount`);
  }

  const B = { ...DEFAULT_BRAND, ...brand };
  const ACCENT = B.accent;

  return new Promise((resolve, reject) => {
    const doc = new PDFDocument({ margin: 50, size: "LETTER" });
    const chunks: Buffer[] = [];
    doc.on("data", (c) => chunks.push(c));
    doc.on("end", () => resolve(Buffer.concat(chunks)));
    doc.on("error", reject);

    const W = 612;
    const L = 50;
    const R = W - L;
    const PAGE_H = 792;

    doc.rect(0, 0, W, 6).fill(ACCENT);

    doc.fontSize(20).font("Helvetica-Bold").fillColor(B.dark)
      .text(data.companyName || "Your Company", L, 22);
    if (data.contractorEmail) {
      doc.fontSize(9).font("Helvetica").fillColor(B.gray).text(data.contractorEmail, L, 46);
    }
    if (data.contractorPhone) {
      doc.fontSize(9).font("Helvetica").fillColor(B.gray).text(data.contractorPhone, L, 57);
    }

    const typeLabel = data.type === "invoice" ? "INVOICE" : "QUOTE";
    doc.fontSize(26).font("Helvetica-Bold").fillColor(ACCENT)
      .text(typeLabel, 400, 22, { width: 162, align: "right" });
    if (data.docNumber) {
      doc.fontSize(10).font("Helvetica").fillColor(B.gray)
        .text(`# ${data.docNumber}`, 400, 54, { width: 162, align: "right" });
    }

    const divY = 76;
    doc.moveTo(L, divY).lineTo(R, divY).strokeColor("#E5E7EB").lineWidth(1).stroke();

    let metaY = divY + 14;
    const dueLabel = data.type === "invoice" ? "DUE DATE" : "VALID UNTIL";
    const metaCols = [
      { label: "DATE", val: fmtDate(data.createdAt), x: L, color: B.dark },
      { label: dueLabel, val: fmtDate(data.dueDate ?? data.validUntil), x: L + 130, color: B.dark },
      {
        label: "STATUS",
        val: statusLabel(data.status),
        x: L + 280,
        color: STATUS_COLORS[data.status ?? ""] ?? B.gray,
      },
    ];
    metaCols.forEach(({ label, val, x, color }) => {
      doc.fontSize(8).font("Helvetica-Bold").fillColor(B.gray).text(label, x, metaY, { width: 120 });
      doc.fontSize(10).font("Helvetica").fillColor(color).text(val, x, metaY + 13, { width: 120 });
    });

    metaY += 40;
    doc.moveTo(L, metaY).lineTo(R, metaY).strokeColor("#E5E7EB").lineWidth(1).stroke();
    metaY += 14;

    doc.fontSize(8).font("Helvetica-Bold").fillColor(B.gray).text("BILL TO", L, metaY);
    doc.fontSize(12).font("Helvetica-Bold").fillColor(B.dark)
      .text(data.customerName || "Customer", L, metaY + 12);
    if (data.customerEmail) {
      doc.fontSize(9).font("Helvetica").fillColor(B.gray).text(data.customerEmail, L, doc.y + 2);
    }
    if (data.customerPhone) {
      doc.fontSize(9).font("Helvetica").fillColor(B.gray).text(data.customerPhone, L, doc.y + 2);
    }

    const jobX = L + 280;
    doc.fontSize(8).font("Helvetica-Bold").fillColor(B.gray)
      .text("JOB / PROJECT", jobX, metaY, { width: R - jobX });
    doc.fontSize(12).font("Helvetica-Bold").fillColor(B.dark)
      .text(data.jobName || "—", jobX, metaY + 12, { width: R - jobX });

    const tableY = Math.max(doc.y, metaY + 60) + 14;

    doc.rect(L, tableY, R - L, 22).fill(ACCENT);
    doc.fontSize(9).font("Helvetica-Bold").fillColor(WHITE);
    doc.text("DESCRIPTION", L + 8, tableY + 7, { width: 230 });
    doc.text("QTY", L + 242, tableY + 7, { width: 50, align: "right" });
    doc.text("UNIT PRICE", L + 296, tableY + 7, { width: 90, align: "right" });
    doc.text("TOTAL", L + 390, tableY + 7, { width: R - L - 390 - 2, align: "right" });

    const items = (data.lineItems ?? []).filter(
      (i) => i.description || i.total || i.amount
    );
    let rowY = tableY + 24;

    if (items.length === 0) {
      doc.rect(L, rowY, R - L, 26).fill(B.light);
      doc.fontSize(10).font("Helvetica").fillColor(B.gray).text("—", L + 8, rowY + 8);
      rowY += 28;
    } else {
      items.forEach((item, idx) => {
        const rh = 26;
        doc.rect(L, rowY, R - L, rh).fill(idx % 2 === 0 ? WHITE : B.light);
        const lineTotal = Number(item.total ?? item.amount ?? 0);
        doc.fontSize(10).font("Helvetica").fillColor(B.dark);
        doc.text(item.description ?? "—", L + 8, rowY + 7, { width: 230 });
        doc.text(String(item.quantity ?? 1), L + 242, rowY + 7, { width: 50, align: "right" });
        doc.text(fmtMoney(Number(item.unit_price ?? 0)), L + 296, rowY + 7, {
          width: 90,
          align: "right",
        });
        doc.text(fmtMoney(lineTotal), L + 390, rowY + 7, {
          width: R - L - 390 - 2,
          align: "right",
        });
        rowY += rh;
      });
    }

    doc.moveTo(L, rowY).lineTo(R, rowY).strokeColor("#E5E7EB").lineWidth(1).stroke();
    rowY += 14;

    const tX = R - 210;
    const tLW = 110;
    const tVW = 92;
    const total = Number(data.total ?? 0);
    const paid = Number(data.amountPaid ?? 0);
    const balance = Number(data.balance ?? total - paid);

    if (paid > 0) {
      doc.fontSize(10).font("Helvetica").fillColor(B.dark)
        .text("Subtotal", tX, rowY, { width: tLW })
        .text(fmtMoney(total), tX + tLW, rowY, { width: tVW, align: "right" });
      rowY += 18;
      doc.fillColor("#10B981")
        .text("Amount Paid", tX, rowY, { width: tLW })
        .text(`–${fmtMoney(paid)}`, tX + tLW, rowY, { width: tVW, align: "right" });
      rowY += 18;
    }

    const balLabel = data.type === "invoice" ? "BALANCE DUE" : "TOTAL";
    doc.rect(tX, rowY, tLW + tVW + 4, 28).fill(ACCENT);
    doc.fontSize(11).font("Helvetica-Bold").fillColor(WHITE)
      .text(balLabel, tX + 6, rowY + 8, { width: tLW })
      .text(fmtMoney(balance), tX + tLW, rowY + 8, { width: tVW - 6, align: "right" });
    rowY += 40;

    if (data.notes?.trim()) {
      doc.moveTo(L, rowY).lineTo(R, rowY).strokeColor("#E5E7EB").lineWidth(1).stroke();
      rowY += 12;
      doc.fontSize(8).font("Helvetica-Bold").fillColor(B.gray).text("NOTES", L, rowY);
      doc.fontSize(10).font("Helvetica").fillColor(B.dark)
        .text(data.notes.trim(), L, rowY + 13, { width: R - L });
    }

    doc.fontSize(9).font("Helvetica").fillColor(B.gray)
      .text("Thank you for your business.", L, PAGE_H - 36, {
        width: R - L,
        align: "center",
      });
    doc.rect(0, PAGE_H - 14, W, 14).fill(ACCENT);

    doc.end();
  });
}
