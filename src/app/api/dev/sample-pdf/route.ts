import { NextResponse } from "next/server";
import { generateDocumentPdf } from "@/lib/pdf/document-pdf";

export const runtime = "nodejs";

function isEnabled(): boolean {
  return process.env.NODE_ENV !== "production" && process.env.ENABLE_DEV_LOGIN === "1";
}

export async function GET() {
  if (!isEnabled()) {
    return new NextResponse("Not found", { status: 404 });
  }

  const pdf = await generateDocumentPdf({
    type: "invoice",
    docNumber: "INV-DEMO-001",
    jobName: "Sample kitchen remodel — 12 Maple St",
    createdAt: new Date().toISOString(),
    dueDate: new Date(Date.now() + 14 * 86_400_000).toISOString(),
    status: "sent",
    total: 12500,
    amountPaid: 5000,
    notes: "Net 14. This PDF is a development-only sample; not a real invoice.",
    companyName: "Acme Plumbing Co.",
    contractorEmail: "billing@acmeplumbing.test",
    contractorPhone: "(555) 010-2030",
    customerName: "Jane Customer",
    customerEmail: "jane@example.test",
    lineItems: [
      { description: "Demolition + haul-away", quantity: 1, unit_price: 2500, total: 2500 },
      { description: "Fixture allowance", quantity: 1, unit_price: 4000, total: 4000 },
      { description: "Labor (40 hrs @ $150)", quantity: 40, unit_price: 150, total: 6000 },
    ],
  });

  return new NextResponse(pdf as unknown as BodyInit, {
    status: 200,
    headers: {
      "content-type": "application/pdf",
      "content-disposition": 'inline; filename="sample-invoice.pdf"',
      "cache-control": "no-store",
    },
  });
}
