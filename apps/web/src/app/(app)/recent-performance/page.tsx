import type { Metadata } from "next";
import { redirect } from "next/navigation";

import { UnauthenticatedError } from "@/auth/errors";
import { RecentPerformanceView } from "@/components/recent-performance/recent-performance-view";
import { AccessFailure } from "@/components/states/access-failure";
import { getRecentPerformanceData } from "@/data/dashboard.server";
import type { RecentPerformanceData } from "@/data/models";

export const metadata: Metadata = { title: "Recent Performance" };

export default async function RecentPerformancePage() {
  let data: RecentPerformanceData;
  try {
    data = await getRecentPerformanceData();
  } catch (error) {
    if (error instanceof UnauthenticatedError) {
      redirect("/sign-in?reason=session-required");
    }
    return <AccessFailure error={error} />;
  }
  return <RecentPerformanceView data={data} />;
}
