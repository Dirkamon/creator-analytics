import { expect, test } from "@playwright/test";

test("shows the private magic-link sign-in boundary with private security headers", async ({
  page,
}) => {
  const response = await page.goto("/sign-in");

  await expect(
    page.getByRole("heading", { name: "Sign in securely" }),
  ).toBeVisible();
  await expect(page.getByLabel("Approved email address")).toBeVisible();
  await expect(
    page.getByRole("button", { name: "Send magic link" }),
  ).toBeVisible();
  await expect(page.getByText("Public registration is disabled")).toBeVisible();
  expect(response?.headers()["cache-control"]).toContain("private, no-store");
  expect(response?.headers()["content-security-policy"]).toContain(
    "frame-ancestors 'none'",
  );
  expect(response?.headers()["x-content-type-options"]).toBe("nosniff");
});

for (const route of [
  "/dashboard",
  "/upcoming-posts",
  "/label-queue",
  "/schedule-approvals",
  "/analytics",
  "/system-status",
]) {
  test(`${route} preserves the private session boundary`, async ({ page }) => {
    const browserDataRequests: string[] = [];
    page.on("request", (request) => {
      if (/\/rest\/v1\/|creator_app/i.test(request.url())) {
        browserDataRequests.push(request.url());
      }
    });

    await page.goto(route);

    await expect(
      page.getByRole("heading", { name: "Sign in securely" }),
    ).toBeVisible();
    await expect(page).toHaveURL(/\/sign-in\?reason=session-required$/);
    await expect(
      page.getByText("Public registration is disabled"),
    ).toBeVisible();
    expect(browserDataRequests).toEqual([]);
  });
}
