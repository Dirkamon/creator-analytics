import { expect, test } from "@playwright/test";

test("shows the private magic-link sign-in boundary", async ({ page }) => {
  await page.goto("/sign-in");

  await expect(
    page.getByRole("heading", { name: "Sign in securely" }),
  ).toBeVisible();
  await expect(page.getByLabel("Approved email address")).toBeVisible();
  await expect(
    page.getByRole("button", { name: "Send magic link" }),
  ).toBeVisible();
  await expect(page.getByText("Public registration is disabled")).toBeVisible();
});

for (const route of [
  "/label-queue",
  "/schedule-approvals",
  "/analytics",
  "/system-status",
]) {
  test(`${route} preserves the private session boundary`, async ({ page }) => {
    await page.goto(route);

    await expect(
      page.getByRole("heading", { name: "Sign in securely" }),
    ).toBeVisible();
    await expect(page).toHaveURL(/\/sign-in\?reason=session-required$/);
    await expect(
      page.getByText("Public registration is disabled"),
    ).toBeVisible();
  });
}
