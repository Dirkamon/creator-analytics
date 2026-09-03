"use client";

import {
  CalendarCheck2,
  CalendarDays,
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

export function Navigation({ compact = false }: { compact?: boolean }) {
  const pathname = usePathname();

  return (
    <nav
      aria-label="Primary navigation"
      className={compact ? "flex gap-2 overflow-x-auto" : "space-y-2"}
    >
      {items.map((item) => {
        const active =
          pathname === item.href || pathname.startsWith(`${item.href}/`);
        const Icon = item.icon;

        return (
          <Link
            aria-current={active ? "page" : undefined}
            className={`flex shrink-0 items-center gap-3 rounded-xl px-3 py-2.5 text-sm font-medium transition ${
              active
                ? "bg-cyan-300 text-slate-950 shadow-[0_10px_28px_rgba(103,232,249,0.16)]"
                : "text-slate-400 hover:bg-white/5 hover:text-white"
            }`}
            href={item.href}
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
