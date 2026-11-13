import { expect, test, type Page } from '@playwright/test';
import { readQaOtp } from './qa-otp';

const adminPhone = '+919990001177';
const orderReference = 'GN-EE01AA8C';

async function signIn(page: Page) {
  await page.goto('/admin/login');
  await page.getByLabel('Administrator mobile number').fill(adminPhone);
  const otpRequest = page.waitForResponse(response =>
    response.url().endsWith('/auth/otp/request') && response.request().method() === 'POST');
  await page.getByRole('button', { name: /Continue securely/ }).click();
  const requested = await otpRequest;
  expect(requested.status()).toBe(202);
  const payload = (await requested.json())?.data;
  expect(payload?.otp_code).toBeUndefined();
  await page.getByLabel('Six-digit verification code').fill(await readQaOtp(payload.challenge_id, adminPhone, payload.expires_at));
  const verified = page.waitForResponse(response =>
    response.url().endsWith('/auth/otp/verify') && response.request().method() === 'POST');
  await page.getByRole('button', { name: /Verify and continue/ }).click();
  expect((await verified).status()).toBe(200);
  await expect(page).toHaveURL(/\/admin\/dashboard$/);
}

test('authorized Admin retries dispatch for the exact QA order', async ({ page }) => {
  await signIn(page);
  await page.getByRole('button', { name: /Delivery Dispatch/ }).click();
  await expect(page.getByRole('heading', { name: 'Dispatch board' })).toBeVisible({ timeout: 30000 });
  const job = page.locator('article').filter({ hasText: orderReference });
  await expect(job).toBeVisible({ timeout: 30000 });
  await expect(job).toContainText('no rider available');
  await job.getByLabel('Audit reason for Admin override').fill('Isolated QA: rider A online; retry exact Kuanpal order dispatch.');
  await job.getByRole('button', { name: 'Retry dispatch' }).click();
  await expect(page.getByRole('alertdialog')).toBeVisible();
  await expect(page.getByRole('alertdialog')).toContainText(orderReference);
  await page.getByLabel(new RegExp(`Type ${orderReference} to confirm`)).fill(orderReference);
  const retry = page.waitForResponse(response =>
    response.url().includes('/admin/delivery-jobs/') && response.request().method() === 'POST' && response.status() === 200);
  await page.getByRole('button', { name: 'Confirm exact target' }).click();
  await retry;
  await expect(job).toContainText('offered', { timeout: 30000 });
  await page.screenshot({ path: 'D:/grepmind-near/docs/phases/evidence/phase3gc_final/admin-retry-offered.png', fullPage: true });
});

test('authorized Admin releases Rider A and advances the exact QA order to reassignment', async ({ page }) => {
  await signIn(page);
  await page.getByRole('button', { name: /Delivery Dispatch/ }).click();
  await expect(page.getByRole('heading', { name: 'Dispatch board' })).toBeVisible({ timeout: 30000 });
  const recovery = page.locator('[data-recovery-case]').filter({ hasText: 'rider reports unable to continue' }).filter({ hasText: orderReference });
  await expect(recovery).toBeVisible({ timeout: 30000 });
  await expect(recovery).toContainText('No handover confirmed');
  await expect(recovery).toContainText('ready_for_pickup');
  await recovery.getByRole('button', { name: 'Release and reassign' }).click();
  const dialog = page.getByRole('alertdialog');
  await expect(dialog).toContainText(orderReference);
  await dialog.getByLabel('Audit reason (10–500 characters)').fill('Isolated QA pre-pickup release after merchant verified no handover.');
  await dialog.getByLabel(new RegExp(`Type ${orderReference} to confirm`)).fill(orderReference);
  const release = page.waitForResponse(response =>
    response.url().includes('/admin/delivery-jobs/') && response.url().endsWith('/recovery') &&
    response.request().method() === 'POST');
  await dialog.getByRole('button', { name: 'Confirm recovery' }).click();
  expect((await release).status()).toBe(200);
  const job = page.locator('article').filter({ hasText: orderReference });
  await expect(job).toContainText('offered', { timeout: 30000 });
  await page.screenshot({ path: 'D:/grepmind-near/docs/phases/evidence/phase3gc_final/admin-released-and-reoffered.png', fullPage: true });
});
