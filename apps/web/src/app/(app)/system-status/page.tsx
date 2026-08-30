import type { Metadata } from "next";
import { redirect } from "next/navigation";

import { UnauthenticatedError } from "@/auth/errors";
import { AccessFailure } from "@/components/states/access-failure";
import { SystemStatusView } from "@/components/system-status/system-status-view";
import type { SystemStatusData } from "@/data/models";
import { getSystemStatusData } from "@/data/system-status.server";

export const metadata: Metadata = { title: "System Status" };

export default async function SystemStatusPage() {
  let data: SystemStatusData;

  try {
    data = await getSystemStatusData();
  } catch (error) {
    if (error instanceof UnauthenticatedError) {
      redirect("/sign-in?reason=session-required");
    }
    return <AccessFailure error={error} />;
  }

  return <SystemStatusView data={data} />;
}
