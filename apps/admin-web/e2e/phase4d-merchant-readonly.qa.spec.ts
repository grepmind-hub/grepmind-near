import { test, expect } from '@playwright/test';
import { readQaOtp } from './qa-otp';

test('Phase 4D merchant sees both reconciled isolated QA settlements', async ({ page }, testInfo) => {
  test.setTimeout(120_000);
  const phone = process.env.E2E_MERCHANT_PHONE_E164;
  const otherBusinessId = process.env.E2E_OTHER_BUSINESS_ID;
  test.skip(!phone, 'Requires the allowlisted isolated QA merchant identity.');
  test.skip(!otherBusinessId, 'Requires a nonmember business ID from isolated QA for live tenant-isolation checks.');

  await page.goto('/', { waitUntil: 'domcontentloaded' });
  // The login label is not associated with the phone input in the current portal markup;
  // target the actual control so this test verifies the live UI rather than a missing label.
  const phoneInput = page.locator('input[type="tel"]');
  await expect(phoneInput).toBeVisible({ timeout: 15_000 });

  const request = page.waitForResponse((response) =>
    response.url().endsWith('/auth/otp/request') && response.request().method() === 'POST', { timeout: 30_000 });
  await phoneInput.fill(phone!);
  await page.getByRole('button', { name: 'Get Verification Code' }).click({ timeout: 10_000 });
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
  await page.getByRole('button', { name: 'Verify & Access Workspace' }).click();
  expect((await verification).status()).toBe(200);
  await expect(page.getByText('Merchant operations', { exact: true })).toBeVisible();

  await page.getByRole('button', { name: 'Payables & settlements' }).click();
  await expect(page.getByRole('heading', { name: 'Payables & settlement history' })).toBeVisible();
  for (const reference of ['GN-0A130595', 'GN-E2F76199']) {
    await expect(page.getByRole('row').filter({ hasText: reference })).toBeVisible();
  }
  const upiRow = page.getByRole('row').filter({ hasText: 'GN-0A130595' });
  await expect(upiRow).toContainText('sandbox upi capture');
  await expect(upiRow).toContainText('₹220.00');
  const codRow = page.getByRole('row').filter({ hasText: 'GN-E2F76199' });
  await expect(codRow).toContainText('synthetic cod collection');
  await expect(codRow).toContainText('₹220.00');
  await expect(page.getByText('reconciled', { exact: true })).toHaveCount(2);
  await expect(page.getByText('Settlement simulation only.', { exact: false })).toBeVisible();
  await expect(page.locator('article').filter({ hasText: 'Pending payable' })).toContainText('₹0.00');
  await expect(page.locator('article').filter({ hasText: 'Simulated / reconciled settlements' })).toContainText('₹440.00');
  const protectedStatuses = await page.evaluate(async (otherBusiness: string) => {
    const token = localStorage.getItem('grepmind_merchant_token');
    if (!token) throw new Error('Authenticated Merchant session token is absent.');
    const getStatus = async (path: string) => (await fetch(`/api/v1${path}`, { headers: { Authorization: `Bearer ${token}` } })).status;
    const business = encodeURIComponent(otherBusiness);
    const [otherOverview, otherPayables, otherSettlements, adminFinance] = await Promise.all([
      getStatus(`/merchant/businesses/${business}/finance/overview`),
      getStatus(`/merchant/businesses/${business}/finance/payables`),
      getStatus(`/merchant/businesses/${business}/finance/settlements`),
      getStatus('/admin/finance/payables'),
    ]);
    return { otherOverview, otherPayables, otherSettlements, adminFinance };
  }, otherBusinessId!);
  expect(protectedStatuses).toEqual({ otherOverview: 404, otherPayables: 404, otherSettlements: 404, adminFinance: 403 });
  await page.screenshot({ path: testInfo.outputPath('merchant-finance.png'), fullPage: true });
  await page.reload();
  await page.getByRole('button', { name: 'Payables & settlements' }).click();
  await expect(page.getByRole('row').filter({ hasText: 'GN-0A130595' })).toBeVisible();
  await expect(page.getByRole('row').filter({ hasText: 'GN-E2F76199' })).toBeVisible();
  await expect(page.locator('article').filter({ hasText: 'Simulated / reconciled settlements' })).toContainText('₹440.00');
});
