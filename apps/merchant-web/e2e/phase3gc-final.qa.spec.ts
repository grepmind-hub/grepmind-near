import { expect, test, type Page } from '@playwright/test';

const merchantPhone = process.env.PHASE3GC_MERCHANT_PHONE!;
const orderReference = process.env.PHASE3GC_ORDER_REFERENCE!;

async function signIn(page: Page) {
  await page.goto('/');
  await page.getByPlaceholder('+91 98765 43210').fill(merchantPhone);
  const otpRequest = page.waitForResponse(response =>
    response.url().endsWith('/auth/otp/request') && response.request().method() === 'POST');
  await page.getByRole('button', { name: 'Get Verification Code' }).click();
  const requested = await otpRequest;
  expect(requested.status()).toBe(202);
  const otp = (await requested.json())?.data?.otp_code as string | undefined;
  expect(otp).toMatch(/^\d{6}$/);
  for (let index = 0; index < 6; index += 1) await page.locator(`#otp-${index}`).fill(otp![index]);
  const verified = page.waitForResponse(response =>
    response.url().endsWith('/auth/otp/verify') && response.request().method() === 'POST');
  await page.getByRole('button', { name: 'Verify & Access Workspace' }).click();
  expect((await verified).status()).toBe(200);
}

test('merchant accepts and starts preparing the exact Phase 3G-C QA order', async ({ page }) => {
  await signIn(page);
  await expect(page.getByRole('button', { name: 'Platform Orders' })).toBeVisible({ timeout: 30000 });
  await page.getByRole('button', { name: 'Platform Orders' }).click();
  await expect(page.getByRole('heading', { name: 'Platform order fulfillment' })).toBeVisible({ timeout: 15000 });
  const order = page.locator('article').filter({ hasText: orderReference });
  await expect(order).toBeVisible({ timeout: 30000 });
  await order.locator('button').first().click();
  await expect(order.getByRole('button', { name: 'Accept order' })).toBeVisible();
  const acceptResponse = page.waitForResponse(response =>
    response.url().includes('/platform-orders/') && response.request().method() === 'POST' && response.status() === 200);
  await order.getByRole('button', { name: 'Accept order' }).click();
  await acceptResponse;
  await expect(order.getByRole('button', { name: 'Start preparation' })).toBeVisible({ timeout: 15000 });
  const prepareResponse = page.waitForResponse(response =>
    response.url().includes('/platform-orders/') && response.request().method() === 'POST' && response.status() === 200);
  await order.getByRole('button', { name: 'Start preparation' }).click();
  await prepareResponse;
  await expect(order).toContainText('Preparing', { timeout: 15000 });
  await page.screenshot({ path: 'D:/grepmind-near/docs/phases/evidence/phase3gc_final/merchant-order-preparing.png', fullPage: true });
});
