import { expect, test, type Page } from '@playwright/test';
import { readQaOtp } from './qa-otp';

const adminPhone = process.env.PHASE3E_QA_ADMIN_PHONE;
const orderReference = process.env.PHASE3E_QA_ORDER_REFERENCE;
const orderId = process.env.PHASE3E_QA_ORDER_ID;
const jobId = process.env.PHASE3E_QA_JOB_ID;

async function signIn(page: Page, phone: string) {
  await page.goto('/admin/login');
  const otpRequest = page.waitForResponse((response) =>
    response.url().endsWith('/auth/otp/request') && response.request().method() === 'POST');
  await page.getByLabel('Administrator mobile number').fill(phone);
  await page.getByRole('button', { name: /Continue securely/ }).click();
  const requested = await otpRequest;
  expect(requested.status()).toBe(202);
  const payload = (await requested.json())?.data;
  expect(payload?.otp_code).toBeUndefined();
  await page.getByLabel('Six-digit verification code').fill(await readQaOtp(payload.challenge_id, phone, payload.expires_at));
  const verified = page.waitForResponse((response) =>
    response.url().endsWith('/auth/otp/verify') && response.request().method() === 'POST');
  await page.getByRole('button', { name: /Verify and continue/ }).click();
  expect((await verified).status()).toBe(200);
  await expect(page).toHaveURL(/\/admin\/dashboard$/);
}

test('Admin dispatch retry requires an exact order-reference confirmation', async ({ page }) => {
  test.skip(!adminPhone || !orderReference || !orderId || !jobId,
    'Set Phase 3E disposable Admin phone, order reference, immutable order ID, and job ID.');
  await signIn(page, adminPhone!);
  await page.getByRole('button', { name: /Delivery Dispatch/ }).click();
  await expect(page.getByRole('heading', { name: 'Dispatch board' })).toBeVisible();

  const search = page.getByLabel('Find an exact order or delivery job');
  await search.fill(orderId!);
  const target = page.locator(`article[data-order-id="${orderId}"]`);
  await expect(target).toHaveCount(1);
  await expect(target).toHaveAttribute('data-job-id', jobId!);
  await expect(target).toContainText(orderReference!);
  await expect(target).toContainText(orderId!);

  await target.getByLabel('Audit reason for Admin override').fill('QA dispatch confirmation safeguard validation');
  await target.getByRole('button', { name: 'Retry dispatch' }).click();
  const dialog = page.getByRole('alertdialog', { name: 'Retry dispatch?' });
  await expect(dialog).toBeVisible();
  await expect(dialog).toContainText(orderReference!);
  await expect(dialog).toContainText(orderId!);
  await expect(dialog).toContainText(jobId!);
  await expect(dialog).toContainText('Phase 3E QA Food Partner');
  await expect(dialog).toContainText('Kuanpal, Cuttack');

  const typedConfirmation = dialog.getByLabel(new RegExp(`Type ${orderReference} to confirm`));
  await typedConfirmation.fill('QA-ED81CEB2');
  const confirmButton = dialog.getByRole('button', { name: 'Confirm exact target' });
  await expect(confirmButton).toBeDisabled();
  await typedConfirmation.fill(orderReference!);
  await expect(confirmButton).toBeEnabled();
  await page.screenshot({ path: '../../docs/phases/evidence/phase3e-admin-exact-dispatch-confirmation.png', fullPage: true });
  await dialog.getByRole('button', { name: 'Cancel' }).click();
  await expect(dialog).toBeHidden();
});
