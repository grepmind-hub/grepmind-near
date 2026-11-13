import { expect, test, type Page } from '@playwright/test';
import { readQaOtp } from './qa-otp';

const merchantPhone = '+919990001172';
const orderReference = 'GN-EE01AA8C';

async function signIn(page: Page) {
  await page.goto('/');
  await page.getByPlaceholder('+91 98765 43210').fill(merchantPhone);
  const otpRequest = page.waitForResponse(response =>
    response.url().endsWith('/auth/otp/request') && response.request().method() === 'POST');
  await page.getByRole('button', { name: 'Get Verification Code' }).click();
  const requested = await otpRequest;
  expect(requested.status()).toBe(202);
  const payload = (await requested.json())?.data;
  expect(payload?.otp_code).toBeUndefined();
  await page.locator('#merchant-otp').fill(await readQaOtp(payload.challenge_id, merchantPhone, payload.expires_at));
  const verified = page.waitForResponse(response =>
    response.url().endsWith('/auth/otp/verify') && response.request().method() === 'POST');
  await page.getByRole('button', { name: 'Verify & Access Workspace' }).click();
  expect((await verified).status()).toBe(200);
}

test('merchant records no-handover for the exact Phase 3G-C QA order', async ({ page }) => {
  await signIn(page);
  await page.getByRole('button', { name: 'Platform Orders' }).click();
  await expect(page.getByRole('heading', { name: 'Platform order fulfillment' })).toBeVisible({ timeout: 30000 });
  const order = page.locator('article').filter({ hasText: orderReference });
  await expect(order).toBeVisible({ timeout: 30000 });
  await order.locator('button').first().click();
  const reason = order.getByPlaceholder('Confirm the goods were not handed to the rider (10–500 characters).');
  await expect(reason).toBeVisible({ timeout: 15000 });
  await reason.fill('Isolated QA confirms no goods were handed to the rider before pickup.');
  const response = page.waitForResponse(result =>
    result.url().includes('/recovery/no-handover') && result.request().method() === 'POST');
  await order.getByRole('button', { name: 'Record partner evidence' }).click();
  expect((await response).status()).toBe(200);
  await expect(order).toContainText('No-handover evidence is recorded for this assignment.', { timeout: 15000 });
  await page.screenshot({ path: '/mnt/d/grepmind-near/docs/phases/evidence/phase3gc_final/merchant-no-handover.png', fullPage: true });
});

test('merchant marks the same Phase 3G-C QA order ready for pickup', async ({ page }) => {
  await signIn(page);
  await page.getByRole('button', { name: 'Platform Orders' }).click();
  await expect(page.getByRole('heading', { name: 'Platform order fulfillment' })).toBeVisible({ timeout: 30000 });
  const order = page.locator('article').filter({ hasText: orderReference });
  await expect(order).toBeVisible({ timeout: 30000 });
  await order.locator('button').first().click();
  const ready = order.getByRole('button', { name: 'Mark ready for pickup' });
  await expect(ready).toBeVisible({ timeout: 15000 });
  const response = page.waitForResponse(result =>
    result.url().includes('/platform-orders/') && result.request().method() === 'POST' && result.status() === 200);
  await ready.click();
  await response;
  await expect(order).toContainText('Ready for pickup', { timeout: 15000 });
  await page.screenshot({ path: '/mnt/d/grepmind-near/docs/phases/evidence/phase3gc_final/merchant-ready-for-pickup.png', fullPage: true });
});
