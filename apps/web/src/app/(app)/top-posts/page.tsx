import type { Metadata } from "next";
import { redirect } from "next/navigation";

import { UnauthenticatedError } from "@/auth/errors";
import { AccessFailure } from "@/components/states/access-failure";
import { TopPostsView } from "@/components/top-posts/top-posts-view";
import { getTopPostsData } from "@/data/dashboard.server";
import type { TopPostsData } from "@/data/models";

export const metadata: Metadata = { title: "Top Posts" };

export default async function TopPostsPage() {
  let data: TopPostsData;

  try {
    data = await getTopPostsData();
  } catch (error) {
    if (error instanceof UnauthenticatedError) {
      redirect("/sign-in?reason=session-required");
    }
    return <AccessFailure error={error} />;
  }

  return <TopPostsView data={data} />;
}
