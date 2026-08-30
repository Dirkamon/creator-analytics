import type { Metadata } from "next";
import { redirect } from "next/navigation";

import { UnauthenticatedError } from "@/auth/errors";
import { AnalyticsView } from "@/components/analytics/analytics-view";
import { AccessFailure } from "@/components/states/access-failure";
import { getAnalyticsData } from "@/data/analytics.server";
import type { AnalyticsData } from "@/data/models";

export const metadata: Metadata = { title: "Analytics" };

export default async function AnalyticsPage() {
  let data: AnalyticsData;

  try {
    data = await getAnalyticsData();
  } catch (error) {
    if (error instanceof UnauthenticatedError) {
      redirect("/sign-in?reason=session-required");
    }
    return <AccessFailure error={error} />;
  }

  return <AnalyticsView data={data} />;
}
