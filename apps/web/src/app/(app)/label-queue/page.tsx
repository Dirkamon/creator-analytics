import type { Metadata } from "next";
import { redirect } from "next/navigation";

import { UnauthenticatedError } from "@/auth/errors";
import { LabelQueueView } from "@/components/label-queue/label-queue-view";
import { AccessFailure } from "@/components/states/access-failure";
import { getLabelQueueData } from "@/data/label-queue.server";
import type { LabelQueueData } from "@/data/models";

export const metadata: Metadata = { title: "Label Queue" };

export default async function LabelQueuePage() {
  let data: LabelQueueData;

  try {
    data = await getLabelQueueData();
  } catch (error) {
    if (error instanceof UnauthenticatedError) {
      redirect("/sign-in?reason=session-required");
    }
    return <AccessFailure error={error} />;
  }

  return <LabelQueueView data={data} />;
}
