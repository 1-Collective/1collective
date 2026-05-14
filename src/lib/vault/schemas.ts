import { z } from "zod";

export const VAULT_BUCKET = "documents";
export const VAULT_PATH_PREFIX = "vault";
export const VAULT_MAX_BYTES = 50 * 1024 * 1024;

export const uploadSchema = z.object({
  name: z.string().trim().min(1, "Name is required").max(255),
  description: z
    .preprocess(
      (v) => (typeof v === "string" && v.trim() === "" ? undefined : v),
      z.string().trim().max(2000).optional()
    ),
});

export const documentIdSchema = z.object({
  document_id: z.string().uuid("Invalid document id"),
});

export type UploadInput = z.infer<typeof uploadSchema>;
export type DocumentIdInput = z.infer<typeof documentIdSchema>;

export function vaultPathFor(tenantId: string, leaf: string): string {
  return `${VAULT_PATH_PREFIX}/${tenantId}/${leaf}`;
}

export function assertVaultPathOwned(storagePath: string, tenantId: string): void {
  const expectedPrefix = `${VAULT_PATH_PREFIX}/${tenantId}/`;
  if (!storagePath.startsWith(expectedPrefix)) {
    throw new Error("Storage path does not belong to the requesting tenant");
  }
}
