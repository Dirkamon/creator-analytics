import type { Metadata } from "next";
import { redirect } from "next/navigation";

import { UnauthenticatedError } from "@/auth/errors";
import { DashboardView } from "@/components/dashboard/dashboard-view";
import { AccessFailure } from "@/components/states/access-failure";
import { getDashboardData } from "@/data/dashboard.server";
import type { DashboardData } from "@/data/models";

export const metadata: Metadata = { title: "Dashboard" };

export default async function DashboardPage() {
  let data: DashboardData;

  try {
    data = await getDashboardData();
  } catch (error) {
    if (error instanceof UnauthenticatedError) {
      redirect("/sign-in?reason=session-required");
    }
    return <AccessFailure error={error} />;
  }

  return <DashboardView data={data} />;
}
