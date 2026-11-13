import { expect, test, type Page } from '@playwright/test';
import { readQaOtp } from './qa-otp';

const phone = process.env.PHASE3E_QA_MERCHANT_PHONE;
const orderReference = process.env.PHASE3E_QA_ORDER_REFERENCE;

async function signInToLocalQA(page: Page, merchantPhone: string) {
  await page.goto('/');
  await page.getByPlaceholder('+91 98765 43210').fill(merchantPhone);
  const otpResponsePromise = page.waitForResponse(response =>
    response.url().endsWith('/auth/otp/request') && response.request().method() === 'POST');
  await page.getByRole('button', { name: /Get Verification Code/ }).click();
  const otpResponse = await otpResponsePromise;
  expect(otpResponse.status()).toBe(202);
  const payload = (await otpResponse.json())?.data;
  expect(payload?.otp_code).toBeUndefined();
  await page.locator('#merchant-otp').fill(await readQaOtp(payload.challenge_id, merchantPhone, payload.expires_at));
  const verifyResponsePromise = page.waitForResponse(response =>
    response.url().endsWith('/auth/otp/verify') && response.request().method() === 'POST');
  await page.getByRole('button', { name: /Verify & Access Workspace/ }).click();
  expect((await verifyResponsePromise).status()).toBe(200);
  await expect(page.getByRole('heading', { name: 'Workspace overview' })).toBeVisible();
}

test('live isolated Merchant Portal fulfills a Phase 3E QA order without API 5xx', async ({ page }) => {
  test.skip(!phone || !orderReference, 'Set Phase 3E isolated QA merchant phone and order reference.');
  const serverErrors: { method: string; path: string; status: number }[] = [];
  const pageErrors: string[] = [];
  page.on('response', response => {
    const url = new URL(response.url());
    if (url.pathname.startsWith('/api/v1/') && response.status() >= 500) {
      serverErrors.push({ method: response.request().method(), path: url.pathname, status: response.status() });
    }
  });
  page.on('pageerror', error => pageErrors.push(error.message));

  await signInToLocalQA(page, phone!);
  await page.getByRole('button', { name: 'Platform Orders' }).click();
  await expect(page.getByRole('heading', { name: 'Platform order fulfillment' })).toBeVisible();
  const targetOrder = page.locator('article').filter({ hasText: orderReference! });
  await expect(targetOrder).toBeVisible();
  await targetOrder.getByRole('button').first().click();
  await expect(targetOrder).toContainText('QA Food Order');
  await expect(targetOrder).toContainText(/Payment remains uncollected/i);
  await expect(targetOrder.getByText(/₹|unit price|supply price/i)).toHaveCount(0);

  await targetOrder.getByRole('button', { name: 'Accept order' }).click();
  await expect(targetOrder).toContainText('Accepted');
  await targetOrder.getByRole('button', { name: 'Start preparation' }).click();
  await expect(targetOrder).toContainText('Preparing');
  await targetOrder.getByRole('button', { name: 'Mark ready for pickup' }).click();
  await expect(targetOrder).toContainText('Ready for pickup');
  await expect(targetOrder).not.toContainText(/delivered|delivery is complete/i);
  await page.waitForTimeout(300);
  expect(serverErrors, `unexpected isolated API errors: ${JSON.stringify(serverErrors)}`).toEqual([]);
  expect(pageErrors, `uncaught browser errors: ${JSON.stringify(pageErrors)}`).toEqual([]);
  await page.screenshot({ path: 'test-results/phase3e-merchant-closeout-ready.png', fullPage: true });
});
