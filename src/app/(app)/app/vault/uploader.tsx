"use client";

import { useRef, useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { uploadVaultDocument } from "@/lib/vault/actions";

export function VaultUploader() {
  const router = useRouter();
  const formRef = useRef<HTMLFormElement>(null);
  const [error, setError] = useState<string | null>(null);
  const [pending, startTransition] = useTransition();

  return (
    <form
      ref={formRef}
      className="space-y-3"
      onSubmit={(e) => {
        e.preventDefault();
        const fd = new FormData(e.currentTarget);
        startTransition(async () => {
          setError(null);
          const result = await uploadVaultDocument(fd);
          if (!result.ok) {
            setError(result.error);
            return;
          }
          formRef.current?.reset();
          router.refresh();
        });
      }}
    >
      <div className="space-y-1.5">
        <Label htmlFor="vault-name">Document name</Label>
        <Input id="vault-name" name="name" type="text" required maxLength={255} />
      </div>
      <div className="space-y-1.5">
        <Label htmlFor="vault-description">Description (optional)</Label>
        <Input id="vault-description" name="description" type="text" maxLength={2000} />
      </div>
      <div className="space-y-1.5">
        <Label htmlFor="vault-file">File</Label>
        <Input id="vault-file" name="file" type="file" required />
        <p className="text-xs text-[var(--color-muted-foreground)]">Up to 50 MB.</p>
      </div>
      {error && <p className="text-sm text-[var(--color-destructive)]">{error}</p>}
      <Button type="submit" disabled={pending}>
        {pending ? "Uploading…" : "Upload to Vault"}
      </Button>
    </form>
  );
}
