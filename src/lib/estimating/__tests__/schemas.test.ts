import { describe, it, expect } from "vitest";
import {
  centsToDollars,
  createEstimateSchema,
  createLineItemSchema,
  lineItemTotalCents,
  moneyDollarsToCents,
  percentToBps,
  quantityToTenThousandths,
  taxCents,
  tenThousandthsToDecimalString,
} from "../schemas";
import { formatNumber } from "../numbering";

describe("estimating money helpers", () => {
  it("converts dollars to cents without float drift", () => {
    expect(moneyDollarsToCents("0.10")).toBe(10);
    expect(moneyDollarsToCents("123.45")).toBe(12345);
    expect(moneyDollarsToCents(0)).toBe(0);
    expect(moneyDollarsToCents(undefined)).toBe(0);
  });

  it("rejects negative or non-finite money", () => {
    expect(() => moneyDollarsToCents(-1)).toThrow();
    expect(() => moneyDollarsToCents("abc")).toThrow();
    expect(() => moneyDollarsToCents(Number.POSITIVE_INFINITY)).toThrow();
  });

  it("rejects money values that exceed the supported maximum", () => {
    expect(() => moneyDollarsToCents(100_000_000)).toThrow();
  });

  it("round-trips cents <-> dollars", () => {
    expect(centsToDollars(12345)).toBe(123.45);
    expect(centsToDollars(0)).toBe(0);
  });

  it("computes line totals from integer ten-thousandths and cents", () => {
    expect(lineItemTotalCents(quantityToTenThousandths("2"), 1500)).toBe(3000);
    expect(lineItemTotalCents(quantityToTenThousandths("1.5"), 1000)).toBe(1500);
  });

  it("rejects bad line totals", () => {
    expect(() => lineItemTotalCents(0, 1000)).toThrow();
    expect(() => lineItemTotalCents(10000, -1)).toThrow();
    expect(() => lineItemTotalCents(Number.NaN, 100)).toThrow();
  });

  it("survives the classic 1.005 float edge case", () => {
    // 1.005 has 3 decimal places — money is restricted to 2.
    expect(() => moneyDollarsToCents("1.005")).toThrow();
    // 1.00 + 1.00 should be exactly 200 cents with no float drift.
    expect(moneyDollarsToCents("1.00") + moneyDollarsToCents("1.00")).toBe(200);
    // 0.10 + 0.20 should be exactly 30 cents.
    expect(moneyDollarsToCents("0.10") + moneyDollarsToCents("0.20")).toBe(30);
  });

  it("computes line totals without float drift on tricky decimals", () => {
    // 3 units at $0.10 each must be exactly 30 cents.
    expect(lineItemTotalCents(quantityToTenThousandths("3"), moneyDollarsToCents("0.10"))).toBe(30);
    // 7 units at $0.07 each must be exactly 49 cents.
    expect(lineItemTotalCents(quantityToTenThousandths("7"), moneyDollarsToCents("0.07"))).toBe(49);
    // 0.3333 quantity at $9.99 -> 0.3333 * 999 = 332.9667 cents -> 333 cents (rounded half-up).
    expect(
      lineItemTotalCents(quantityToTenThousandths("0.3333"), moneyDollarsToCents("9.99"))
    ).toBe(333);
  });

  it("stringifies ten-thousandths back to a four-decimal string", () => {
    expect(tenThousandthsToDecimalString(15000)).toBe("1.5000");
    expect(tenThousandthsToDecimalString(1)).toBe("0.0001");
    expect(tenThousandthsToDecimalString(123456789)).toBe("12345.6789");
  });

  it("converts percent strings to basis points without float drift", () => {
    expect(percentToBps("8.25")).toBe(825);
    expect(percentToBps("0")).toBe(0);
    expect(percentToBps("100")).toBe(10000);
    expect(percentToBps("8.255")).toBe(826);
    expect(() => percentToBps("100.01")).toThrow();
    expect(() => percentToBps("-1")).toThrow();
  });

  it("computes tax in cents from basis points", () => {
    expect(taxCents(10000, 825)).toBe(825);
    expect(taxCents(0, 825)).toBe(0);
    expect(taxCents(10000, 0)).toBe(0);
  });

  it("rejects tax rates outside [0, 10000] bps", () => {
    expect(() => taxCents(100, -1)).toThrow();
    expect(() => taxCents(100, 10001)).toThrow();
  });
});

describe("createEstimateSchema", () => {
  it("requires a non-empty title", () => {
    const r = createEstimateSchema.safeParse({ title: "" });
    expect(r.success).toBe(false);
  });

  it("converts a percent string to basis points", () => {
    const r = createEstimateSchema.parse({ title: "Job", tax_rate_percent: "8.25" });
    expect(r.tax_rate_percent).toBe(825);
  });

  it("rejects an out-of-range tax rate", () => {
    expect(() =>
      createEstimateSchema.parse({ title: "Job", tax_rate_percent: "150" })
    ).toThrow();
  });

  it("normalizes empty optional fields to null", () => {
    const r = createEstimateSchema.parse({
      title: "Job",
      company_id: "",
      project_id: "",
      valid_until: "",
    });
    expect(r.company_id).toBeNull();
    expect(r.project_id).toBeNull();
    expect(r.valid_until).toBeNull();
  });
});

describe("createLineItemSchema", () => {
  it("converts a price string into integer cents", () => {
    const r = createLineItemSchema.parse({
      estimate_id: "11111111-1111-4111-8111-111111111111",
      description: "Shingles",
      quantity: "10",
      unit: "bundle",
      unit_price: "45.99",
    });
    expect(r.quantity).toBe(100000);
    expect(r.unit_price).toBe(4599);
  });

  it("rejects zero or negative quantity", () => {
    expect(() =>
      createLineItemSchema.parse({
        estimate_id: "11111111-1111-4111-8111-111111111111",
        description: "x",
        quantity: "0",
        unit: "ea",
        unit_price: "1",
      })
    ).toThrow();
  });
});

describe("estimate numbering format", () => {
  it("zero-pads the sequence to four digits", () => {
    expect(formatNumber(2026, 1)).toBe("EST-2026-0001");
    expect(formatNumber(2026, 42)).toBe("EST-2026-0042");
    expect(formatNumber(2030, 1234)).toBe("EST-2030-1234");
  });
});
