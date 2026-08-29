"use client";

import { UnexpectedErrorState } from "@/components/states/feedback-states";

export default function ErrorBoundary({ reset }: { reset: () => void }) {
  return <UnexpectedErrorState retry={reset} />;
}
