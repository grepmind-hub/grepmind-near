import { chromium, expect, test as base } from '@playwright/test';
import { readQaOtp } from './qa-otp';

const profile = process.env.QA_ADMIN_CHROME_PROFILE;
const test = profile ? base.extend({
  page: async ({ baseURL }, use) => {
    const context = await chromium.launchPersistentContext(profile, {
      baseURL,
      headless: false,
      channel: 'chrome',
    });
    try {
      await use(context.pages()[0] ?? await context.newPage());
    } finally {
      await context.close();
    }
  },
}) : base;

test('AUTH-OTP-02 automatically enters one fresh Admin OTP through the real login UI', async ({ page }) => {
  const manualEntry = process.env.QA_OTP_MANUAL_ENTRY === '1';
  const keepBrowserOpen = process.env.QA_ADMIN_KEEP_BROWSER_OPEN === '1';
  if (manualEntry) test.setTimeout(180_000);
  if (keepBrowserOpen) test.setTimeout(0);
  const adminPhone = process.env.E2E_ADMIN_PHONE_E164;
  test.skip(!adminPhone || !process.env.QA_OTP_READER_URL || !process.env.QA_OTP_RUN_ID,
    'Requires a synthetic allowlisted Admin and scoped isolated QA reader.');

  const pinStatus = profile
    ? page.waitForResponse((response) => response.url().endsWith('/api/v1/auth/admin-mpin'))
    : undefined;
  await page.goto('/admin/login');
  await expect(page.getByRole('heading', { name: 'Admin sign in' })).toBeVisible();
  if (pinStatus && (await (await pinStatus).json()).data?.enrolled === true) {
    if (process.env.QA_ADMIN_USE_OTP === '1') {
      await page.getByRole('button', { name: 'Use OTP instead' }).click();
    } else {
      await expect(page.getByLabel('Six-digit PIN')).toBeVisible();
      console.log('This Chrome profile is enrolled. Enter your PIN in Chrome to sign in.');
      await page.waitForEvent('close', { timeout: 0 });
      return;
    }
  }
  const waitForRequest = () => page.waitForResponse((response) =>
    response.url().endsWith('/auth/otp/request') && response.request().method() === 'POST', {
    timeout: manualEntry ? 0 : 30_000,
  });
  const request = waitForRequest();
  await page.getByLabel('Administrator mobile number').fill(adminPhone!);
  await page.getByRole('button', { name: 'Continue securely' }).click();
  let response = await request;
  while (response.status() === 429 && keepBrowserOpen) {
    const nextRequest = waitForRequest();
    console.log('OTP requests are rate-limited. Chrome will stay open. Wait for the cooldown, then click Continue securely again.');
    response = await nextRequest;
  }
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
  const verify = page.getByRole('button', { name: 'Verify and continue' });
  const waitForVerification = () => page.waitForResponse((item) =>
    item.url().endsWith('/auth/otp/verify') && item.request().method() === 'POST', {
    timeout: manualEntry ? 0 : 30_000,
  });
  let verification = waitForVerification();
  if (manualEntry) {
    // The operator explicitly enables manual mode in the visible QA browser.
    await expect(field).toBeVisible();
    console.log(`MANUAL QA OTP (short-lived; do not copy into logs): ${code}`);
    console.log('Enter the OTP in Chrome, then click Verify and continue.');
  } else {
    await field.fill(code);
    await verify.click();
  }
  let verifyResponse = await verification;
  while (verifyResponse.status() === 401 && manualEntry && keepBrowserOpen) {
    verification = waitForVerification();
    console.log('OTP verification was rejected. Chrome will stay open for another attempt.');
    verifyResponse = await verification;
  }
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

  if (session.data.admin_mpin_enrollment_available === true) {
    await expect(page.getByLabel('New six-digit PIN')).toBeVisible();
    if (keepBrowserOpen) {
      console.log('Admin OTP verified. PIN setup is open in the visible Chrome window.');
      await page.waitForEvent('close', { timeout: 0 });
      return;
    }
    await page.getByRole('button', { name: 'Skip for now' }).click();
  }

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
