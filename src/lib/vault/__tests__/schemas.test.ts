import { describe, expect, test } from "vitest";
import {
  assertVaultPathOwned,
  documentIdSchema,
  uploadSchema,
  vaultPathFor,
} from "../schemas";

describe("uploadSchema", () => {
  test("accepts valid input with optional description", () => {
    const r = uploadSchema.safeParse({ name: "Master Service Agreement", description: "v3" });
    expect(r.success).toBe(true);
  });

  test("trims name and rejects empty", () => {
    expect(uploadSchema.safeParse({ name: "   " }).success).toBe(false);
    expect(uploadSchema.safeParse({ name: "" }).success).toBe(false);
  });

  test("rejects oversized name", () => {
    expect(uploadSchema.safeParse({ name: "x".repeat(256) }).success).toBe(false);
  });

  test("treats empty-string description as undefined", () => {
    const r = uploadSchema.safeParse({ name: "ok", description: "" });
    expect(r.success).toBe(true);
    if (r.success) expect(r.data.description).toBeUndefined();
  });
});

describe("documentIdSchema", () => {
  test("accepts a valid uuid", () => {
    expect(
      documentIdSchema.safeParse({ document_id: "550e8400-e29b-41d4-a716-446655440000" }).success
    ).toBe(true);
  });

  test("rejects garbage", () => {
    expect(documentIdSchema.safeParse({ document_id: "not-a-uuid" }).success).toBe(false);
    expect(documentIdSchema.safeParse({}).success).toBe(false);
  });
});

describe("vaultPathFor / assertVaultPathOwned (IDOR guards)", () => {
  const tenantA = "11111111-1111-1111-1111-111111111111";
  const tenantB = "22222222-2222-2222-2222-222222222222";

  test("vaultPathFor produces tenant-prefixed path", () => {
    expect(vaultPathFor(tenantA, "doc-id-filename")).toBe(
      `vault/${tenantA}/doc-id-filename`
    );
  });

  test("assertVaultPathOwned accepts a path owned by the tenant", () => {
    expect(() =>
      assertVaultPathOwned(`vault/${tenantA}/whatever-here`, tenantA)
    ).not.toThrow();
  });

  test("assertVaultPathOwned rejects another tenant's path (cross-tenant IDOR)", () => {
    expect(() =>
      assertVaultPathOwned(`vault/${tenantB}/foreign-doc`, tenantA)
    ).toThrow(/does not belong/);
  });

  test("rejects a path with no vault/ prefix at all", () => {
    expect(() =>
      assertVaultPathOwned(`logos/${tenantA}/something.png`, tenantA)
    ).toThrow(/does not belong/);
  });

  test("rejects a sibling-prefix attack (vault/{tenantA}.../)", () => {
    expect(() =>
      assertVaultPathOwned(`vault/${tenantA}-evil/doc`, tenantA)
    ).toThrow(/does not belong/);
  });

  test("rejects an empty path", () => {
    expect(() => assertVaultPathOwned("", tenantA)).toThrow(/does not belong/);
  });
});
