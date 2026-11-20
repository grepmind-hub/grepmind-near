import { chromium, expect, test } from '@playwright/test';
import { randomInt } from 'node:crypto';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { readQaOtp } from './qa-otp';

test('an enrolled browser profile signs in by PIN after closing and reopening', async ({ baseURL }) => {
  test.skip(
    !['http://localhost:18305', 'http://127.0.0.1:18306'].includes(baseURL ?? '') ||
      !(process.env.QA_OTP_RUN_ID?.startsWith('mpin-reopen-') || process.env.QA_OTP_RUN_ID?.startsWith('phase5p3-')),
    'Requires a dedicated disposable Admin PIN reopening stack.',
  );
  const phone = '+919990000200';
  const pin = String(randomInt(100000, 1000000));
  const profile = await mkdtemp(join(tmpdir(), 'grepmind-admin-pin-'));
  try {
    const first = await chromium.launchPersistentContext(profile, { baseURL });
    try {
      const page = first.pages()[0];
      page.on('console', (message) => console.log(`[browser:${message.type()}] ${message.text()}`));
      page.on('requestfailed', (request) => console.log(`[request-failed] ${request.method()} ${request.url()} ${request.failure()?.errorText ?? ''}`));
      page.on('response', async (response) => {
        if (new URL(response.url()).pathname.startsWith('/api/v1/')) {
          console.log(`[api] ${response.status()} ${new URL(response.url()).pathname}`);
        }
      });
      await page.goto('/admin/login');
      await page.getByLabel('Administrator mobile number').fill(phone);
      const challengeWait = page.waitForResponse((response) => response.url().endsWith('/auth/otp/request'));
      await page.getByRole('button', { name: 'Continue securely' }).click();
      const challenge = await challengeWait;
      expect(challenge.status()).toBe(202);
      const { data } = await challenge.json();
      const code = await readQaOtp(data.challenge_id, phone, data.expires_at);
      await page.getByLabel('Six-digit verification code').fill(code);
      await page.getByRole('button', { name: 'Verify and continue' }).click();
      await page.getByLabel('New six-digit PIN').fill(pin);
      await page.getByLabel('Confirm PIN').fill(pin);
      const enrollment = page.waitForResponse((response) => response.url().endsWith('/auth/admin-mpin/enroll'));
      await page.getByRole('button', { name: 'Save PIN' }).click();
      expect((await enrollment).status()).toBe(204);
      await expect(page.getByRole('heading', { name: 'Platform pulse' })).toBeVisible();
      await page.getByTitle('Sign out of Admin Session').click();
      await expect(page.getByLabel('Administrator mobile number')).toBeVisible();
    } finally {
      await first.close();
    }

    const reopened = await chromium.launchPersistentContext(profile, { baseURL });
    try {
      const page = reopened.pages()[0];
      page.on('console', (message) => console.log(`[reopened-browser:${message.type()}] ${message.text()}`));
      page.on('requestfailed', (request) => console.log(`[reopened-request-failed] ${request.method()} ${request.url()} ${request.failure()?.errorText ?? ''}`));
      page.on('response', async (response) => {
        if (new URL(response.url()).pathname.startsWith('/api/v1/')) {
          console.log(`[reopened-api] ${response.status()} ${new URL(response.url()).pathname}`);
        }
      });
      let otpRequests = 0;
      page.on('request', (request) => {
        if (request.url().endsWith('/auth/otp/request')) otpRequests++;
      });
      await page.goto('/admin/login');
      await page.getByLabel('Six-digit PIN', { exact: true }).fill(pin);
      await expect(page.getByLabel('Administrator mobile number')).toHaveCount(0);
      const verification = page.waitForResponse((response) => response.url().endsWith('/auth/admin-mpin/verify'));
      await page.getByRole('button', { name: 'Verify PIN' }).click();
      expect((await verification).status()).toBe(200);
      await expect(page.getByRole('heading', { name: 'Platform pulse' })).toBeVisible();
      expect(otpRequests).toBe(0);
    } finally {
      await reopened.close();
    }
  } finally {
    await rm(profile, { recursive: true, force: true });
  }
});
