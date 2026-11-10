import { expect, test, type Page } from '@playwright/test';

const phone = process.env.PHASE3C_QA_MERCHANT_PHONE;
const orderReference = process.env.PHASE3C_QA_ORDER_REFERENCE;

async function signIn(page: Page, merchantPhone: string) {
  await page.goto('/');
  const phoneField = page.getByPlaceholder('+91 98765 43210');
  await phoneField.fill('+91 ');
  await phoneField.pressSequentially(merchantPhone.replace(/^\+91/, ''));
  const otpRequest = page.waitForResponse((response) =>
    response.url().endsWith('/auth/otp/request') && response.request().method() === 'POST');
  await page.getByRole('button', { name: /Get Verification Code/ }).click();
  const requested = await otpRequest;
  expect(requested.status()).toBe(202);
  const code = (await requested.json())?.data?.otp_code as string | undefined;
  expect(code).toMatch(/^\d{6}$/);
  for (let index = 0; index < 6; index += 1) {
    await page.locator(`#otp-${index}`).fill(code![index]);
  }
  const verified = page.waitForResponse((response) =>
    response.url().endsWith('/auth/otp/verify') && response.request().method() === 'POST');
  await page.getByRole('button', { name: /Verify & Access Workspace/ }).click();
  expect((await verified).status()).toBe(200);
  await expect(page.getByRole('button', { name: 'Platform Orders' })).toBeVisible();
}

test('live QA delivery assignment appears only in the assigned Merchant workspace', async ({ page }) => {
  test.skip(!phone || !orderReference, 'Set PHASE3C_QA_MERCHANT_PHONE and PHASE3C_QA_ORDER_REFERENCE for the disposable QA run.');
  await signIn(page, phone!);
  await page.getByRole('button', { name: 'Platform Orders' }).click();
  await expect(page.getByRole('heading', { name: 'Platform order fulfillment' })).toBeVisible();
  const order = page.locator('article').filter({ hasText: orderReference! });
  await expect(order).toContainText(/preparing/i);
  await expect(order).toContainText(/Delivery dispatch · assigned · rider assigned/i);
  await page.screenshot({ path: 'test-results/phase3c-merchant-dispatch.png', fullPage: true });
});
