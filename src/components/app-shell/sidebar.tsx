"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { cn } from "@/lib/utils";

export interface NavItem {
  label: string;
  href: string;
  icon: React.ReactNode;
  badge?: string;
}

export function Sidebar({
  title,
  subtitle,
  items,
  footer,
}: {
  title: string;
  subtitle?: string;
  items: NavItem[];
  footer?: React.ReactNode;
}) {
  const pathname = usePathname();

  return (
    <aside className="flex h-screen w-60 flex-col border-r bg-[var(--color-background)]">
      <div className="px-5 py-4">
        <div className="text-sm font-semibold tracking-tight">{title}</div>
        {subtitle && (
          <div className="mt-0.5 text-xs text-[var(--color-muted-foreground)]">
            {subtitle}
          </div>
        )}
      </div>

      <nav className="flex-1 space-y-0.5 overflow-y-auto px-2 py-2 scrollbar-thin">
        {items.map((item) => {
          const isActive =
            pathname === item.href ||
            (item.href !== "/app" && item.href !== "/admin" && pathname.startsWith(item.href));
          return (
            <Link
              key={item.href}
              href={item.href}
              className={cn(
                "flex items-center justify-between gap-2 rounded-md px-3 py-1.5 text-sm transition-colors",
                isActive
                  ? "bg-[var(--color-accent)] text-[var(--color-accent-foreground)] font-medium"
                  : "text-[var(--color-muted-foreground)] hover:bg-[var(--color-muted)] hover:text-[var(--color-foreground)]"
              )}
            >
              <span className="flex items-center gap-2">
                {item.icon}
                {item.label}
              </span>
              {item.badge && (
                <span className="rounded bg-[var(--color-muted)] px-1.5 py-0.5 text-[10px] uppercase tracking-wide text-[var(--color-muted-foreground)]">
                  {item.badge}
                </span>
              )}
            </Link>
          );
        })}
      </nav>

      {footer && <div className="border-t px-3 py-3">{footer}</div>}
    </aside>
  );
}
