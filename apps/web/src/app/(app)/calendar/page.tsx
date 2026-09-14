import type { Metadata } from "next";
import { redirect } from "next/navigation";
import { UnauthenticatedError } from "@/auth/errors";
import { AccessFailure } from "@/components/states/access-failure";
import { CalendarView } from "@/components/calendar/calendar-view";
import { getCalendarData } from "@/data/calendar.server";
import type { CalendarData } from "@/data/calendar";

export const metadata: Metadata = { title: "Calendar" };

export default async function CalendarPage({
  searchParams,
}: {
  searchParams: Promise<{ month?: string | string[] }>;
}) {
  let data: CalendarData;
  try {
    const { month } = await searchParams;
    data = await getCalendarData({ month });
  } catch (error) {
    if (error instanceof UnauthenticatedError)
      redirect("/sign-in?reason=session-required");
    return <AccessFailure error={error} />;
  }
  return <CalendarView key={data.month} data={data} />;
}
