import { expect, test, type Page } from '@playwright/test';

const phone = process.env.PHASE3C_QA_ADMIN_PHONE;
const orderReference = process.env.PHASE3C_QA_ORDER_REFERENCE;
const riderName = process.env.PHASE3C_QA_RIDER_NAME ?? 'QA Phase3C Rider';
const expectedDispatchState = process.env.PHASE3C_EXPECT_DISPATCH_STATE ?? 'assigned';

async function signIn(page: Page, adminPhone: string) {
  await page.goto('/admin/login');
  const otpRequest = page.waitForResponse((response) =>
    response.url().endsWith('/auth/otp/request') && response.request().method() === 'POST');
  const phoneField = page.getByLabel('Administrator mobile number');
  await phoneField.fill('');
  await phoneField.pressSequentially(adminPhone.replace(/^\+91/, ''));
  await page.getByRole('button', { name: /Continue securely/ }).click();
  const requested = await otpRequest;
  expect(requested.status()).toBe(202);
  const code = (await requested.json())?.data?.otp_code as string | undefined;
  expect(code).toMatch(/^\d{6}$/);
  await page.getByLabel('Six-digit verification code').fill(code!);
  const verified = page.waitForResponse((response) =>
    response.url().endsWith('/auth/otp/verify') && response.request().method() === 'POST');
  await page.getByRole('button', { name: /Verify and continue/ }).click();
  expect((await verified).status()).toBe(200);
  await expect(page).toHaveURL(/\/admin\/dashboard$/);
}

test('live QA delivery assignment appears in the Admin dispatch board', async ({ page }) => {
  test.skip(!phone || !orderReference, 'Set PHASE3C_QA_ADMIN_PHONE and PHASE3C_QA_ORDER_REFERENCE for the disposable QA run.');
  await signIn(page, phone!);
  await page.getByRole('button', { name: /Delivery Dispatch/ }).click();
  await expect(page.getByRole('heading', { name: 'Dispatch board' })).toBeVisible();
  const job = page.locator('article').filter({ hasText: orderReference! });
  await expect(job).toBeVisible();
  if (expectedDispatchState === 'offered' && await job.getByRole('button', { name: 'Retry dispatch' }).isVisible()) {
    await job.getByLabel('Audit reason for Admin override').fill('QA dispatch retry after approved rider came online.');
    await job.getByRole('button', { name: 'Retry dispatch' }).click();
  }
  await expect(job).toContainText(expectedDispatchState, { timeout: 30_000 });
  if (expectedDispatchState === 'assigned') await expect(job).toContainText(riderName);
  await job.getByRole('button', { name: 'View dispatch history' }).click();
  await expect(job.getByText(/rider assigned/i).first()).toBeVisible();
  await page.screenshot({ path: 'test-results/phase3c-admin-dispatch.png', fullPage: true });
});
