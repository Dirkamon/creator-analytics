import { notFound, redirect } from "next/navigation";
import { ForbiddenError, UnauthenticatedError } from "@/auth/errors";
import { ConfigurationError } from "@/config/errors";
import { isPreferencesUiAvailable } from "@/config/preferences-server";
import { loadSchedulingPreferences } from "@/data/preferences.server";
import { PostingPreferencesForm } from "@/components/preferences/posting-preferences-form";
import { AccessFailure } from "@/components/states/access-failure";

export default async function SchedulingPreferencesPage() {
  if (!isPreferencesUiAvailable()) notFound();
  let data;
  try {
    data = await loadSchedulingPreferences();
  } catch (error) {
    if (error instanceof UnauthenticatedError)
      redirect("/sign-in?reason=session-required");
    if (error instanceof ForbiddenError) return <AccessFailure error={error} />;
    return (
      <section className="section-card" role="alert">
        <h1 className="text-xl font-semibold">
          Scheduling preferences are unavailable
        </h1>
        <p className="text-secondary mt-3">
          {error instanceof ConfigurationError
            ? "The restricted settings connection still needs to be configured."
            : "The saved settings or coverage could not be loaded. Reload to try again."}{" "}
          No settings or posts were changed.
        </p>
      </section>
    );
  }
  return <PostingPreferencesForm {...data} />;
}
