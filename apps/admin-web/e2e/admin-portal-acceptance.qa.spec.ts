import { execFileSync } from 'node:child_process';
import { randomInt } from 'node:crypto';
import { expect, test } from '@playwright/test';
import { readQaOtp } from './qa-otp';

test('one QA Admin can enroll a PIN and use all read-only finance views', async ({ page, baseURL }, testInfo) => {
  test.skip(
    baseURL !== 'http://localhost:18305' || !process.env.QA_OTP_RUN_ID?.startsWith('admin-acceptance-'),
    'Requires the dedicated disposable Admin acceptance stack.',
  );
  const phone = '+919990000183';
  const pin = String(randomInt(100000, 1000000));
  const get = (path: string) => page.waitForResponse((response) =>
    new URL(response.url()).pathname === `/api/v1${path}` && response.request().method() === 'GET',
  );

  await page.goto('/admin/login');
  await page.getByLabel('Administrator mobile number').fill(phone);
  const otpRequest = page.waitForResponse((response) => response.url().endsWith('/auth/otp/request'));
  await page.getByRole('button', { name: 'Continue securely' }).click();
  const challenge = await otpRequest;
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
  await expect(page).toHaveURL(/\/admin\/dashboard$/);

  await page.getByTitle('Sign out of Admin Session').click();
  await expect(page).toHaveURL(/\/admin\/login$/);
  await page.getByLabel('Six-digit PIN').fill(pin);
  const pinVerify = page.waitForResponse((response) => response.url().endsWith('/auth/admin-mpin/verify'));
  const userAccess = get('/admin/user-access');
  await page.getByRole('button', { name: 'Verify PIN' }).click();
  expect((await pinVerify).status()).toBe(200);
  await expect(page).toHaveURL(/\/admin\/dashboard$/);
  expect((await (await userAccess).json()).meta.can_manage_roles).toBe(false);

  const summary = [
    ['/admin/payments/refunds', 'Refunds', '₹90.00'],
    ['/admin/cod/remittances', 'COD remittances', '₹280.00'],
    ['/admin/finance/payables', 'Posted merchant payables', '₹199.50'],
    ['/admin/finance/settlements', 'Merchant settlement simulations', '₹199.50'],
  ] as const;
  const summaryReads = summary.map(([path]) => get(path));
  await page.getByRole('button', { name: /Finance overview/ }).click();
  for (const [index, [, title, amount]] of summary.entries()) {
    const response = await summaryReads[index];
    expect(response.status()).toBe(200);
    expect((await response.json()).data).toHaveLength(1);
    await expect(page.getByRole('table', { name: title })).toContainText(amount);
  }
  await page.screenshot({ path: testInfo.outputPath('finance-overview.png'), fullPage: true });

  const captured = execFileSync('docker', [
    'exec', '-e', 'PGOPTIONS=-c default_transaction_read_only=on', 'grepmind_5c_qa_db',
    'psql', '-XAt', '-v', 'ON_ERROR_STOP=1', '-U', 'qa4d', '-d', 'grepmind_5c_qa', '-c',
    `SELECT o.reference_code FROM customer_orders o JOIN payment_refunds r ON r.order_id=o.id`,
  ], { encoding: 'utf8' }).trim();
  expect(captured).toMatch(/^GN-[A-F0-9]{8}$/);
  await page.getByRole('button', { name: /Payment tracking/ }).click();
  await page.getByLabel('Order reference or UUID').fill(captured);
  const attempts = get(`/admin/payments/orders/${captured}`);
  await page.getByRole('button', { name: 'Look up order' }).click();
  expect((await attempts).status()).toBe(200);
  await expect(page.getByRole('table', { name: 'Payment attempts' })).toContainText('succeeded');
  await expect(page.getByRole('table', { name: 'Reconciliation history' })).toContainText('matched');

  const queueRead = get('/admin/payments/reconciliation-queue');
  await page.getByRole('button', { name: /Reconciliation queue/ }).click();
  const queueResponse = await queueRead;
  expect(queueResponse.status()).toBe(200);
  const queue = (await queueResponse.json()).data;
  expect(queue).toHaveLength(1);
  expect(queue[0]).toMatchObject({ kind: 'action_required', attempt_status: 'reconciliation_required' });
  const action = page.getByRole('table', { name: 'Needs action' }).getByRole('row').filter({ hasText: queue[0].reference_code });
  const details = get(`/admin/payments/orders/${queue[0].order_id}`);
  await action.getByRole('link', { name: queue[0].reference_code }).click();
  expect((await details).status()).toBe(200);
  await expect(page.getByRole('heading', { name: queue[0].reference_code })).toBeVisible();
  await expect(page.getByRole('table', { name: 'Reconciliation history' })).toContainText('amount mismatch');
});
