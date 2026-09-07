"use client";

import {
  CalendarCheck2,
  CalendarDays,
  CalendarRange,
  ChartNoAxesCombined,
  LayoutDashboard,
  ListOrdered,
  ServerCog,
  Tags,
} from "lucide-react";
import Link from "next/link";
import { usePathname } from "next/navigation";

const items = [
  { href: "/dashboard", label: "Dashboard", icon: LayoutDashboard },
  { href: "/top-posts", label: "Top Posts", icon: ListOrdered },
  { href: "/calendar", label: "Calendar", icon: CalendarRange },
  { href: "/upcoming-posts", label: "Upcoming Posts", icon: CalendarDays },
  { href: "/label-queue", label: "Label Queue", icon: Tags },
  {
    href: "/schedule-approvals",
    label: "Schedule Approvals",
    icon: CalendarCheck2,
  },
  { href: "/analytics", label: "Analytics", icon: ChartNoAxesCombined },
  { href: "/system-status", label: "System Status", icon: ServerCog },
];

export function Navigation({
  compact = false,
  previewPath,
}: {
  compact?: boolean;
  previewPath?: string;
}) {
  const pathname = usePathname();

  return (
    <nav
      aria-label="Primary navigation"
      className={compact ? "flex gap-2 overflow-x-auto pb-1" : "space-y-1.5"}
    >
      {items.map((item) => {
        const active =
          (previewPath ?? pathname) === item.href ||
          (previewPath ?? pathname).startsWith(`${item.href}/`);
        const Icon = item.icon;

        return (
          <Link
            aria-current={active ? "page" : undefined}
            className={`flex shrink-0 items-center gap-3 rounded-xl px-3 py-2.5 text-sm font-medium transition ${
              active
                ? "bg-accent/10 text-accent ring-accent/20 ring-1 ring-inset"
                : "text-muted hover:bg-surface-raised hover:text-foreground"
            }`}
            href={
              previewPath
                ? `/design-preview?view=${item.href.slice(1)}`
                : item.href
            }
            key={item.href}
          >
            <Icon aria-hidden size={17} />
            {item.label}
          </Link>
        );
      })}
    </nav>
  );
}
