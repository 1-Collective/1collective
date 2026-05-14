import { requireTenantUser } from "@/lib/auth/session";
import { createAdminClient } from "@/lib/supabase/admin";
import { isModuleEnabled } from "@/foundational/registry";
import { ModuleStatus } from "@/components/app-shell/module-status";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { formatDate } from "@/lib/utils";
import { downloadVaultDocument, deleteVaultDocument } from "@/lib/vault/actions";
import { VaultUploader } from "./uploader";

function formatBytes(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
}

export default async function VaultPage() {
  const session = await requireTenantUser();

  if (!isModuleEnabled("vault")) {
    return (
      <ModuleStatus
        kind="coming_soon"
        title="Vault"
        description="Encrypted, tenant-scoped document storage on Supabase Storage."
      />
    );
  }

  const admin = createAdminClient();
  const { data: documents } = await admin
    .from("cc_vault_documents")
    .select("id, name, description, mime_type, size_bytes, created_at")
    .eq("tenant_id", session.tenantId)
    .order("created_at", { ascending: false });

  const docs = documents ?? [];

  return (
    <div className="p-8">
      <h1 className="text-2xl font-semibold tracking-tight">Vault</h1>
      <p className="mt-1 text-sm text-[var(--color-muted-foreground)]">
        Encrypted, tenant-scoped document storage. Files are private by default and only
        accessible through short-lived signed URLs.
      </p>

      <div className="mt-6 grid gap-6 lg:grid-cols-[1fr_360px]">
        <div className="space-y-3">
          {docs.length === 0 ? (
            <Card>
              <CardContent className="py-12 text-center text-sm text-[var(--color-muted-foreground)]">
                No documents yet. Upload your first file to the right.
              </CardContent>
            </Card>
          ) : (
            docs.map((d) => (
              <Card key={d.id}>
                <CardContent className="flex items-center justify-between gap-4 py-4">
                  <div className="min-w-0">
                    <div className="truncate font-medium">{d.name}</div>
                    {d.description && (
                      <div className="truncate text-xs text-[var(--color-muted-foreground)]">
                        {d.description}
                      </div>
                    )}
                    <div className="mt-1 text-xs text-[var(--color-muted-foreground)]">
                      {formatBytes(d.size_bytes)} · {d.mime_type ?? "unknown type"} ·{" "}
                      {formatDate(d.created_at)}
                    </div>
                  </div>
                  <div className="flex shrink-0 gap-2">
                    <form action={downloadVaultDocument}>
                      <input type="hidden" name="document_id" value={d.id} />
                      <Button type="submit" variant="outline" size="sm">
                        Download
                      </Button>
                    </form>
                    <form action={deleteVaultDocument}>
                      <input type="hidden" name="document_id" value={d.id} />
                      <Button type="submit" variant="ghost" size="sm">
                        Delete
                      </Button>
                    </form>
                  </div>
                </CardContent>
              </Card>
            ))
          )}
        </div>

        <Card>
          <CardHeader>
            <CardTitle className="text-base">Upload to Vault</CardTitle>
            <CardDescription>
              Files are stored encrypted at rest in Supabase Storage and never publicly accessible.
            </CardDescription>
          </CardHeader>
          <CardContent>
            <VaultUploader />
          </CardContent>
        </Card>
      </div>
    </div>
  );
}
