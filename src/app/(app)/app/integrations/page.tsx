import { requireTenantUser } from "@/lib/auth/session";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { FOUNDATIONAL_MODULES, missingCredentialsFor, type FoundationalModuleKey } from "@/foundational/registry";

const VISIBLE: FoundationalModuleKey[] = [
  "ai_core",
  "ai_phone_daniella",
  "ai_phone_serana",
  "social_amber",
  "google_sync",
  "quickbooks_sync",
  "integrations_oauth",
];

export default async function IntegrationsPage() {
  await requireTenantUser();

  return (
    <div className="p-8">
      <h1 className="text-2xl font-semibold tracking-tight">Integrations</h1>
      <p className="mt-1 text-sm text-[var(--color-muted-foreground)]">
        External services connected to your workspace. Each integration must have its credentials provided before the module that depends on it becomes usable.
      </p>

      <div className="mt-6 grid gap-3 lg:grid-cols-2">
        {VISIBLE.map((key) => {
          const module = FOUNDATIONAL_MODULES[key];
          const missing = missingCredentialsFor(key);
          const ready = missing.length === 0 && module.requiredCredentials.length > 0;
          const isOptional = module.requiredCredentials.length === 0;
          return (
            <Card key={key}>
              <CardHeader>
                <div className="flex items-center justify-between">
                  <CardTitle className="text-base">{module.name}</CardTitle>
                  {isOptional ? (
                    <Badge variant="secondary">No credentials</Badge>
                  ) : ready ? (
                    <Badge variant="default">Ready</Badge>
                  ) : (
                    <Badge variant="destructive">Setup required</Badge>
                  )}
                </div>
                {module.notes && <CardDescription>{module.notes}</CardDescription>}
              </CardHeader>
              {missing.length > 0 && (
                <CardContent>
                  <div className="text-xs text-[var(--color-muted-foreground)] mb-2">
                    Missing environment variables:
                  </div>
                  <div className="flex flex-wrap gap-1.5">
                    {missing.map((m) => (
                      <code
                        key={m}
                        className="rounded bg-[var(--color-muted)] px-1.5 py-0.5 text-[11px]"
                      >
                        {m}
                      </code>
                    ))}
                  </div>
                </CardContent>
              )}
            </Card>
          );
        })}
      </div>
    </div>
  );
}
