import { test, expect } from '@playwright/test';
import { readQaOtp } from './qa-otp';

test('Phase 4D scoped finance grant uses independent Admin issuer and approver', async ({ page }) => {
  test.setTimeout(180_000);
  const phone = process.env.E2E_ADMIN_PHONE_E164;
  const target = process.env.E2E_FINANCE_GRANT_TARGET_ID;
  const action = process.env.E2E_FINANCE_GRANT_ACTION;
  const batchIds = (process.env.E2E_SETTLEMENT_BATCH_IDS ?? '').split(',').map((id) => id.trim()).filter(Boolean);
  test.skip(!phone || !action || ((action === 'request' || action === 'approve') && !target) || ((action === 'simulate' || action === 'reconcile') && batchIds.length === 0), 'Requires an allowlisted QA Admin and action-specific isolated QA identifiers.');

  await page.goto('/admin/login');
  await expect(page.getByRole('heading', { name: 'Admin sign in' })).toBeVisible();
  const request = page.waitForResponse((response) =>
    response.url().endsWith('/auth/otp/request') && response.request().method() === 'POST');
  await page.getByLabel('Administrator mobile number').fill(phone!);
  await page.getByRole('button', { name: 'Continue securely' }).click();
  const response = await request;
  expect(response.status()).toBe(202);
  const body = await response.json();
  expect(body?.data?.otp_code).toBeUndefined();
  const challenge = body?.data?.challenge_id as string;
  expect(challenge).toMatch(/^[0-9a-f-]{36}$/i);
  const otp = await readQaOtp(challenge, phone!, body?.data?.expires_at as string);
  await page.getByLabel('Six-digit verification code').fill(otp);
  const verification = page.waitForResponse((item) =>
    item.url().endsWith('/auth/otp/verify') && item.request().method() === 'POST');
  await page.getByRole('button', { name: 'Verify and continue' }).click();
  expect((await verification).status()).toBe(200);
  await expect(page).toHaveURL(/\/admin\/dashboard$/);

  await page.getByRole('button', { name: /Merchant settlements/ }).click();
  if (action === 'simulate' || action === 'reconcile') {
    await expect(page.getByRole('heading', { name: 'Merchant payables & settlement simulation' })).toBeVisible();
  } else {
    await expect(page.getByRole('heading', { name: 'Finance access · two-person control' })).toBeVisible();
  }

  if (action === 'request') {
    for (const permission of ['finance.read', 'finance.post'] as const) {
      await page.getByLabel('Target Admin user ID').fill(target!);
      await page.getByLabel('Permission').selectOption(permission);
      await page.getByLabel('Request reason').fill(`Temporary isolated QA simulator ${permission} grant`);
      await page.getByRole('button', { name: 'Submit access request' }).click();
      await expect(page.getByText('Request submitted. A different Finance administrator must approve it.')).toBeVisible();
      await expect(page.getByText(`${permission} · ${target}`)).toBeVisible();
    }
  } else if (action === 'approve') {
    for (const permission of ['finance.read', 'finance.post'] as const) {
      const row = page.locator('div.rounded-xl.border.p-3').filter({ hasText: `${permission} · ${target}` });
      await expect(row).toBeVisible();
      await row.locator('input[placeholder="Independent decision reason (10+ chars)"]').fill(`Independent QA approval for ${permission}`);
      await row.getByRole('button', { name: 'approve' }).click();
      await expect(row.getByText('approved')).toBeVisible();
    }
  } else if (action === 'simulate' || action === 'reconcile') {
    page.on('dialog', async (dialog) => { await dialog.accept(); });
    for (const id of batchIds) {
      const input = page.getByLabel(`Settlement reason ${id}`);
      const card = input.locator('..');
      if (action === 'simulate') {
        await expect(card.getByText('approved', { exact: true })).toBeVisible();
        await input.fill(`Authorized isolated QA simulation for batch ${id}; no payout`);
        await card.getByRole('button', { name: 'simulate' }).click();
        await expect(card.getByText('simulated', { exact: true })).toBeVisible();
      } else {
        await expect(card.getByText('simulated', { exact: true })).toBeVisible();
        await input.fill(`Independent read-only reconciliation of simulated batch ${id}`);
        await card.getByRole('button', { name: 'reconcile' }).click();
        await expect(card.getByText('reconciled', { exact: true })).toBeVisible();
      }
    }
  } else {
    throw new Error('Unsupported finance access or settlement action.');
  }

  const logout = page.waitForResponse((item) =>
    item.url().endsWith('/auth/logout') && item.request().method() === 'POST');
  await page.getByTitle('Sign out of Admin Session').click();
  expect((await logout).status()).toBe(200);
  await expect(page).toHaveURL(/\/admin\/login$/);
});
