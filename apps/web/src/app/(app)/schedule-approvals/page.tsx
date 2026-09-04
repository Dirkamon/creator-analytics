import type { Metadata } from "next";
import { redirect } from "next/navigation";

import { UnauthenticatedError } from "@/auth/errors";
import { ScheduleApprovalsView } from "@/components/schedule-approvals/schedule-approvals-view";
import { AccessFailure } from "@/components/states/access-failure";
import { getServerEnvironment } from "@/config/env-server";
import type { ScheduleApprovalsData } from "@/data/models";
import { getScheduleApprovalsData } from "@/data/schedule-approvals.server";

export const metadata: Metadata = { title: "Schedule Approvals" };

export default async function ScheduleApprovalsPage() {
  let data: ScheduleApprovalsData;
  let decisionsEnabled = false;

  try {
    decisionsEnabled =
      getServerEnvironment().CREATOR_ANALYTICS_SCHEDULE_DECISIONS_ENABLED;
    data = await getScheduleApprovalsData();
  } catch (error) {
    if (error instanceof UnauthenticatedError) {
      redirect("/sign-in?reason=session-required");
    }
    return <AccessFailure error={error} />;
  }

  return (
    <ScheduleApprovalsView data={data} decisionsEnabled={decisionsEnabled} />
  );
}
