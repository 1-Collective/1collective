"use server";

import { redirect } from "next/navigation";
import { revalidatePath } from "next/cache";
import { nanoid } from "nanoid";
import { requireTenantUser } from "@/lib/auth/session";
import { createAdminClient } from "@/lib/supabase/admin";
import { isModuleEnabled } from "@/foundational/registry";
import { actionError, actionOk, parseForm, type ActionResult } from "@/lib/validation";
import { log } from "@/lib/log";
import {
  VAULT_BUCKET,
  VAULT_MAX_BYTES,
  assertVaultPathOwned,
  documentIdSchema,
  uploadSchema,
  vaultPathFor,
} from "./schemas";

function safeFilename(name: string): string {
  return name.replace(/[^a-zA-Z0-9._-]+/g, "_").slice(0, 200);
}

function ensureVaultEnabled() {
  if (!isModuleEnabled("vault")) throw new Error("Vault module is disabled");
}

export async function uploadVaultDocument(formData: FormData): Promise<ActionResult> {
  ensureVaultEnabled();
  const session = await requireTenantUser();

  const file = formData.get("file");
  if (!(file instanceof File) || file.size === 0) {
    return actionError("Please choose a file to upload.");
  }
  if (file.size > VAULT_MAX_BYTES) {
    return actionError(`File exceeds the ${VAULT_MAX_BYTES / (1024 * 1024)} MB limit.`);
  }

  const parsed = parseForm(uploadSchema, formData);
  if (!parsed.ok) return parsed;

  const admin = createAdminClient();
  const docId = crypto.randomUUID();
  const path = vaultPathFor(
    session.tenantId,
    `${docId}-${safeFilename(file.name)}-${nanoid(8)}`
  );

  const buffer = Buffer.from(await file.arrayBuffer());
  const { error: uploadError } = await admin.storage
    .from(VAULT_BUCKET)
    .upload(path, buffer, {
      contentType: file.type || "application/octet-stream",
      upsert: false,
    });
  if (uploadError) {
    log.error("vault.upload.storage_failed", {
      tenant_id: session.tenantId,
      user_id: session.userId,
      err: uploadError.message,
    });
    return actionError("Storage upload failed. Please try again.");
  }

  const { error: insertError } = await admin.from("cc_vault_documents").insert({
    id: docId,
    tenant_id: session.tenantId,
    name: parsed.data.name,
    description: parsed.data.description ?? null,
    mime_type: file.type || null,
    size_bytes: file.size,
    storage_path: path,
    uploaded_by: session.userId,
  });
  if (insertError) {
    await admin.storage.from(VAULT_BUCKET).remove([path]);
    log.error("vault.upload.row_insert_failed", {
      tenant_id: session.tenantId,
      user_id: session.userId,
      err: insertError.message,
    });
    return actionError("Could not record the document. Please try again.");
  }

  log.info("vault.upload.success", {
    tenant_id: session.tenantId,
    user_id: session.userId,
    document_id: docId,
    size_bytes: file.size,
  });
  revalidatePath("/app/vault");
  return actionOk();
}

export async function downloadVaultDocument(formData: FormData): Promise<void> {
  ensureVaultEnabled();
  const session = await requireTenantUser();

  const parsed = documentIdSchema.safeParse({
    document_id: formData.get("document_id"),
  });
  if (!parsed.success) throw new Error("Invalid document id");

  const admin = createAdminClient();
  const { data: doc } = await admin
    .from("cc_vault_documents")
    .select("storage_path, tenant_id")
    .eq("id", parsed.data.document_id)
    .maybeSingle();

  if (!doc || doc.tenant_id !== session.tenantId) {
    throw new Error("Document not found");
  }
  assertVaultPathOwned(doc.storage_path, session.tenantId);

  const { data: signed, error } = await admin.storage
    .from(VAULT_BUCKET)
    .createSignedUrl(doc.storage_path, 60);
  if (error || !signed) throw new Error("Could not generate download link");

  log.info("vault.download.signed", {
    tenant_id: session.tenantId,
    user_id: session.userId,
    document_id: parsed.data.document_id,
  });
  redirect(signed.signedUrl);
}

export async function deleteVaultDocument(formData: FormData): Promise<void> {
  ensureVaultEnabled();
  const session = await requireTenantUser();

  const parsed = documentIdSchema.safeParse({
    document_id: formData.get("document_id"),
  });
  if (!parsed.success) throw new Error("Invalid document id");

  const admin = createAdminClient();
  const { data: doc } = await admin
    .from("cc_vault_documents")
    .select("id, storage_path, tenant_id")
    .eq("id", parsed.data.document_id)
    .maybeSingle();

  if (!doc || doc.tenant_id !== session.tenantId) {
    throw new Error("Document not found");
  }
  assertVaultPathOwned(doc.storage_path, session.tenantId);

  const { error: delRowErr } = await admin.from("cc_vault_documents").delete().eq("id", doc.id);
  if (delRowErr) {
    log.error("vault.delete.row_failed", {
      tenant_id: session.tenantId,
      document_id: doc.id,
      err: delRowErr.message,
    });
    throw new Error("Could not delete the document.");
  }
  await admin.storage.from(VAULT_BUCKET).remove([doc.storage_path]);

  log.info("vault.delete.success", {
    tenant_id: session.tenantId,
    user_id: session.userId,
    document_id: doc.id,
  });
  revalidatePath("/app/vault");
}
