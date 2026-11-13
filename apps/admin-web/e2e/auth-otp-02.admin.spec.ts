import { test, expect } from '@playwright/test';
import { readQaOtp } from './qa-otp';

test('AUTH-OTP-02 automatically enters one fresh Admin OTP through the real login UI', async ({ page }) => {
  const manualEntry = process.env.QA_OTP_MANUAL_ENTRY === '1';
  const keepBrowserOpen = process.env.QA_ADMIN_KEEP_BROWSER_OPEN === '1';
  if (manualEntry) test.setTimeout(180_000);
  if (keepBrowserOpen) test.setTimeout(0);
  const adminPhone = process.env.E2E_ADMIN_PHONE_E164;
  test.skip(!adminPhone || !process.env.QA_OTP_READER_URL || !process.env.QA_OTP_RUN_ID,
    'Requires a synthetic allowlisted Admin and scoped isolated QA reader.');

  await page.goto('/admin/login');
  await expect(page.getByRole('heading', { name: 'Admin sign in' })).toBeVisible();
  const request = page.waitForResponse((response) =>
    response.url().endsWith('/auth/otp/request') && response.request().method() === 'POST');
  await page.getByLabel('Administrator mobile number').fill(adminPhone!);
  await page.getByRole('button', { name: 'Continue securely' }).click();
  const response = await request;
  if (response.status() !== 202) {
    const payload = await response.json().catch(() => ({}));
    const code = payload?.error?.code;
    const message = payload?.error?.message;
    throw new Error(`OTP request failed with HTTP ${response.status()}${code ? ` (${code})` : ''}${message ? `: ${message}` : ''}`);
  }
  const body = await response.json();
  expect(body?.data?.otp_code).toBeUndefined();
  const challengeId = body?.data?.challenge_id as string;
  expect(challengeId).toMatch(/^[0-9a-f-]{36}$/i);
  const code = await readQaOtp(challengeId, adminPhone!, body?.data?.expires_at as string);

  const field = page.getByLabel('Six-digit verification code');
  if (manualEntry) {
    // Explicit local QA fallback only. The ordinary path keeps the code in
    // memory and fills the UI automatically; manual mode is opt-in and headed.
    console.log(`MANUAL QA OTP (short-lived; do not copy into logs): ${code}`);
    await expect(field).toBeVisible();
    await expect(field).toHaveValue(/^\d{6}$/, { timeout: 120_000 });
  } else {
    await field.fill(code);
    await expect(field).toHaveValue(/^\d{6}$/);
  }
  const verify = page.getByRole('button', { name: 'Verify and continue' });
  const verified = page.waitForResponse((item) =>
    item.url().endsWith('/auth/otp/verify') && item.request().method() === 'POST');
  await verify.click();
  const verifyResponse = await verified;
  expect(verifyResponse.status()).toBe(200);
  const session = await verifyResponse.json();
  expect(session?.data?.access_token).toBeTruthy();

  const replay = await page.evaluate(async ({ phone, otp, challenge }) => {
    const result = await fetch('/api/v1/auth/otp/verify', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ phone_e164: phone, otp_code: otp, challenge_id: challenge }),
    });
    return result.status;
  }, { phone: adminPhone!, otp: code, challenge: challengeId });
  expect(replay).toBe(401);

  await expect(page).toHaveURL(/\/admin\/dashboard$/);
  await expect(page.getByText('Executive command center')).toBeVisible();
  await expect(page.getByText('Trend intelligence')).toBeVisible();
  await page.screenshot({ path: '../../docs/phases/evidence/auth-otp-02/admin-dashboard.png' });
  if (keepBrowserOpen) {
    console.log('Admin authenticated. Close the visible Chrome window when you are finished.');
    await page.waitForEvent('close', { timeout: 0 });
    return;
  }
  const logout = page.waitForResponse((item) =>
    item.url().endsWith('/auth/logout') && item.request().method() === 'POST');
  await page.getByTitle('Sign out of Admin Session').click();
  expect((await logout).status()).toBe(200);
  await expect(page).toHaveURL(/\/admin\/login$/);
});
