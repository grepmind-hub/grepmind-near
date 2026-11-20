import { expect, test } from '@playwright/test';

test('finance overview shows server records and keeps section failures independent', async ({ page }) => {
  await page.addInitScript(() => sessionStorage.setItem('admin_access_token', 'mock-browser-session'));

  const financeMethods: string[] = [];
  let payableDenied = true;
  await page.route('**/api/v1/admin/**', async (route) => {
    const url = new URL(route.request().url());
    const path = url.pathname;
    const currency = 'INR';
    if (/\/admin\/(finance|cod|payments)\//.test(path)) {
      financeMethods.push(route.request().method());
    }
    if (path.endsWith('/finance/payables')) {
      if (payableDenied) return route.fulfill({ status: 403, json: {} });
      return route.fulfill({ json: { data: [{
        id: 'payable-1', reference_code: 'GN-PAYABLE', merchant_name: 'QA Bakery',
        net_payable_minor: 12500, payment_source: 'upi', currency,
      }] } });
    }
    if (path.endsWith('/payments/refunds') && url.searchParams.get('status') === 'requested') {
      return route.fulfill({ json: { data: [{
        id: 'refund-1', order_id: '00000000-0000-4000-8000-000000000123', amount_minor: 9000, status: 'requested', currency,
      }, {
        id: 'refund-2', reference_code: '../invalid', amount_minor: 100, status: 'requested', currency,
      }] } });
    }
    if (path.endsWith('/cod/remittances')) {
      return route.fulfill({ json: { data: [{
        id: 'remittance-1', submission_reference: 'COD-123', rider_name: 'QA Rider',
        amount_minor: 20500, state: 'verified', currency,
      }] } });
    }
    if (path.endsWith('/finance/settlements')) {
      return route.fulfill({ json: { data: [{
        id: 'batch-1', merchant_name: 'QA Bakery', simulated_net_minor: 12500, status: 'reconciled', currency,
      }] } });
    }
    if (path.endsWith('/admin/trends')) {
      return route.fulfill({ json: { data: { series: [], categories: [] } } });
    }
    return route.fulfill({ json: { data: [] } });
  });

  await page.goto('/admin/dashboard');
  await page.getByRole('button', { name: /Finance overview/ }).click();
  await expect(page.getByRole('heading', { name: 'Finance overview' })).toBeVisible();
  await expect(page.getByRole('region', { name: 'Posted merchant payables' }).getByRole('alert')).toHaveText('Active Platform Admin access is required.');
  const refunds = page.getByRole('table', { name: 'Refunds' });
  await expect(refunds.getByRole('link', { name: 'View order by ID' })).toHaveAttribute('href',
    /payment-tracking\/00000000-0000-4000-8000-000000000123\?from=finance-overview/);
  const missingReference = refunds.getByRole('row').filter({ hasText: 'Reference unavailable' });
  await expect(missingReference).toContainText('Classification unavailable');
  await expect(missingReference.getByRole('link')).toHaveCount(0);
  await expect(page.getByRole('table', { name: 'COD remittances' })).toContainText('₹205.00');
  await expect(page.getByRole('table', { name: 'Merchant settlement simulations' })).toContainText('Reconciled');
  await expect(page.getByRole('region', { name: 'Merchant settlement simulations' }).getByText('Classification unavailable')).toBeVisible();

  const refundFilter = page.getByLabel('Refund status');
  await refundFilter.focus();
  await refundFilter.selectOption('succeeded');
  await expect(page.getByText('No refunds with this status.')).toBeVisible();
  await expect(refundFilter).toBeFocused();

  payableDenied = false;
  await page.getByRole('button', { name: 'Refresh finance data' }).click();
  await expect(page.getByRole('table', { name: 'Posted merchant payables' })).toContainText('GN-PAYABLE');
  expect(financeMethods.length).toBeGreaterThanOrEqual(8);
  expect([...new Set(financeMethods)]).toEqual(['GET']);

  await page.getByRole('button', { name: 'Open COD accountability' }).click();
  await expect(page.getByRole('heading', { name: 'COD cash accountability' })).toBeVisible();
});

test('isolated Platform Admin can read finance without a separate grant', async ({ page }) => {
  const phone = process.env.E2E_FINANCE_OVERVIEW_ADMIN;
  test.skip(!phone || !process.env.QA_OTP_READER_URL, 'Set the isolated QA reader and a synthetic Admin without finance.read.');
  const { readQaOtp } = await import('./qa-otp');

  await page.goto('/admin/login');
  await page.getByLabel('Administrator mobile number').fill(phone!);
  const challengeResponse = page.waitForResponse((response) => response.url().endsWith('/auth/otp/request'));
  await page.getByRole('button', { name: 'Continue securely' }).click();
  const challenge = await challengeResponse;
  expect(challenge.status()).toBe(202);
  const { data } = await challenge.json();
  const otp = await readQaOtp(data.challenge_id, phone!, data.expires_at);

  await page.getByLabel('Six-digit verification code').fill(otp);
  const otpVerified = page.waitForResponse((response) => response.url().endsWith('/auth/otp/verify'));
  await page.getByRole('button', { name: 'Verify and continue' }).click();
  const verified = await otpVerified;
  expect(verified.status()).toBe(200);
  if ((await verified.json()).data.admin_mpin_enrollment_available === true) {
    await page.getByRole('button', { name: 'Skip for now' }).click();
  }
  await expect(page).toHaveURL(/\/admin\/dashboard$/);

  const paths = [
    '/admin/payments/refunds', '/admin/cod/remittances', '/admin/finance/payables', '/admin/finance/settlements',
  ];
  const reads = paths.map((path) => page.waitForResponse((response) =>
    new URL(response.url()).pathname === `/api/v1${path}` && response.request().method() === 'GET',
  ));
  await page.getByRole('button', { name: /Finance overview/ }).click();
  for (const response of await Promise.all(reads)) expect(response.status()).toBe(200);

  const queueResponse = page.waitForResponse((response) => response.url().endsWith('/admin/payments/reconciliation-queue'));
  await page.getByRole('button', { name: /Reconciliation queue/ }).click();
  expect((await queueResponse).status()).toBe(200);
  await expect(page.getByRole('region', { name: 'Payment reconciliation queue' }).getByRole('alert')).toHaveCount(0);

  const denied = await page.evaluate(async () => {
    const token = sessionStorage.getItem('admin_access_token');
    const response = await fetch('/api/v1/admin/finance/orders/00000000-0000-4000-8000-000000000001/accrue-payable', {
      method: 'POST',
      headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
      body: '{}',
    });
    return response.status;
  });
  expect(denied).toBe(403);
});
