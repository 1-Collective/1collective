import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { AlertTriangle, Clock, KeyRound } from "lucide-react";

export type ModuleStatusKind = "coming_soon" | "setup_required";

export function ModuleStatus({
  kind,
  title,
  description,
  setupItems,
}: {
  kind: ModuleStatusKind;
  title: string;
  description: string;
  setupItems?: string[];
}) {
  const isSetup = kind === "setup_required";
  return (
    <div className="p-8">
      <div className="flex items-center gap-3">
        <h1 className="text-2xl font-semibold tracking-tight">{title}</h1>
        <Badge variant={isSetup ? "destructive" : "secondary"}>
          {isSetup ? "Attention needed" : "Coming soon"}
        </Badge>
      </div>
      <p className="mt-1 text-sm text-[var(--color-muted-foreground)]">
        {description}
      </p>

      <Card className="mt-6 max-w-2xl">
        <CardHeader>
          <CardTitle className="flex items-center gap-2 text-base">
            {isSetup ? (
              <AlertTriangle className="h-4 w-4 text-[var(--color-warning)]" />
            ) : (
              <Clock className="h-4 w-4 text-[var(--color-muted-foreground)]" />
            )}
            {isSetup ? "Setup required before this module is usable" : "Module not yet implemented"}
          </CardTitle>
          <CardDescription>
            {isSetup
              ? "The backend wiring is in place but credentials have not been provided."
              : "The backend and UI for this module are scheduled for an upcoming build phase."}
          </CardDescription>
        </CardHeader>
        {isSetup && setupItems && setupItems.length > 0 && (
          <CardContent>
            <div className="space-y-2 text-sm">
              {setupItems.map((item) => (
                <div key={item} className="flex items-start gap-2">
                  <KeyRound className="mt-0.5 h-3.5 w-3.5 flex-shrink-0 text-[var(--color-muted-foreground)]" />
                  <code className="text-xs">{item}</code>
                </div>
              ))}
            </div>
          </CardContent>
        )}
      </Card>
    </div>
  );
}
