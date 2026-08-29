import type { Metadata } from "next";
import { redirect } from "next/navigation";

import { UnauthenticatedError } from "@/auth/errors";
import { AccessFailure } from "@/components/states/access-failure";
import { UpcomingPostsView } from "@/components/upcoming/upcoming-posts-view";
import type { UpcomingPostsData } from "@/data/models";
import { getUpcomingPostsData } from "@/data/upcoming.server";

export const metadata: Metadata = { title: "Upcoming Posts" };

export default async function UpcomingPostsPage() {
  let data: UpcomingPostsData;

  try {
    data = await getUpcomingPostsData();
  } catch (error) {
    if (error instanceof UnauthenticatedError) {
      redirect("/sign-in?reason=session-required");
    }
    return <AccessFailure error={error} />;
  }

  return <UpcomingPostsView data={data} />;
}
