import { execFileSync } from 'node:child_process';
import { expect, test } from '@playwright/test';
import { readQaOtp } from './qa-otp';

test('disposable QA finance overview reads records without a finance grant', async ({ page, baseURL }) => {
  test.skip(
    baseURL !== 'http://127.0.0.1:18305' || !process.env.QA_OTP_RUN_ID?.startsWith('phase5c-'),
    'Requires the dedicated Phase 5C disposable stack.',
  );
  const targetPhone = '+919990000183';
  const sections = [
    { path: '/admin/payments/refunds', title: 'Refunds', empty: 'No refunds with this status.' },
    { path: '/admin/finance/payables', title: 'Posted merchant payables', empty: 'No posted merchant payables.' },
    { path: '/admin/cod/remittances', title: 'COD remittances', empty: 'No COD remittances recorded.' },
    { path: '/admin/finance/settlements', title: 'Merchant settlement simulations', empty: 'No merchant settlement batches.' },
  ];

  await page.goto('/admin/login');
  await page.getByLabel('Administrator mobile number').fill(targetPhone);
  const challengeWait = page.waitForResponse((r) => r.url().endsWith('/auth/otp/request'));
  await page.getByRole('button', { name: 'Continue securely' }).click();
  const challenge = await challengeWait;
  expect(challenge.status()).toBe(202);
  const { data } = await challenge.json();
  const otp = await readQaOtp(data.challenge_id, targetPhone, data.expires_at);
  await page.getByLabel('Six-digit verification code').fill(otp);
  await page.getByRole('button', { name: 'Verify and continue' }).click();
  await expect(page).toHaveURL(/\/admin\/dashboard$/);

  const waitForReads = () => Promise.all(sections.map(({ path }) =>
    page.waitForResponse((r) => new URL(r.url()).pathname === `/api/v1${path}` && r.request().method() === 'GET'),
  ));
  const allowed = waitForReads();
  await page.getByRole('button', { name: /Finance overview/ }).click();
  for (const response of await allowed) {
    expect(response.status()).toBe(200);
    expect((await response.json()).data ?? []).toEqual([]);
  }
  for (const section of sections) {
    await expect(page.getByRole('region', { name: section.title }).getByText(section.empty)).toBeVisible();
  }
});

test('disposable QA finance overview matches populated PostgreSQL records', async ({ page, baseURL }, testInfo) => {
  test.skip(
    baseURL !== 'http://127.0.0.1:18305' || !process.env.QA_OTP_RUN_ID?.startsWith('phase5c-'),
    'Requires the dedicated Phase 5C disposable stack and domain-generated finance records.',
  );

  const projections = [
    {
      path: '/admin/payments/refunds', title: 'Refunds',
      query: "SELECT id::text, order_id::text, amount_minor, currency, status FROM payment_refunds WHERE status='requested'",
      display: ['order_id', 'amount_minor', 'status'],
    },
    {
      path: '/admin/finance/payables', title: 'Posted merchant payables',
      query: 'SELECT p.id::text, o.reference_code, b.name merchant_name, p.net_payable_minor, p.currency, p.payment_source FROM merchant_payable_snapshots p JOIN customer_orders o ON o.id=p.order_id JOIN businesses b ON b.id=p.business_id',
      display: ['reference_code', 'merchant_name', 'net_payable_minor', 'payment_source'],
    },
    {
      path: '/admin/cod/remittances', title: 'COD remittances',
      query: 'SELECT r.id::text, r.submission_reference, p.display_name rider_name, r.amount_minor, r.currency, r.state FROM cod_remittances r JOIN rider_profiles p ON p.user_id=r.rider_user_id',
      display: ['submission_reference', 'rider_name', 'amount_minor', 'state'],
    },
    {
      path: '/admin/finance/settlements', title: 'Merchant settlement simulations',
      query: 'SELECT s.id::text, b.name merchant_name, s.simulated_net_minor, s.currency, s.status FROM merchant_settlement_batches s JOIN businesses b ON b.id=s.business_id',
      display: ['merchant_name', 'simulated_net_minor', 'status'],
    },
  ];

  const phone = '+919990000183';
  await page.goto('/admin/login');
  await page.getByLabel('Administrator mobile number').fill(phone);
  const challengeWait = page.waitForResponse((response) => response.url().endsWith('/auth/otp/request'));
  await page.getByRole('button', { name: 'Continue securely' }).click();
  const challenge = await challengeWait;
  expect(challenge.status()).toBe(202);
  const { data } = await challenge.json();
  const otp = await readQaOtp(data.challenge_id, phone, data.expires_at);
  await page.getByLabel('Six-digit verification code').fill(otp);
  await page.getByRole('button', { name: 'Verify and continue' }).click();
  await expect(page).toHaveURL(/\/admin\/dashboard$/);

  const reads = projections.map(({ path }) =>
    page.waitForResponse((response) => new URL(response.url()).pathname === `/api/v1${path}` && response.request().method() === 'GET'),
  );
  await page.getByRole('button', { name: /Finance overview/ }).click();

  for (const [index, projection] of projections.entries()) {
    const response = await reads[index];
    expect(response.status()).toBe(200);
    const sql = `SELECT row_to_json(record) FROM (${projection.query}) AS record`;
    const lines = execFileSync('docker', [
      'exec', '-e', 'PGOPTIONS=-c default_transaction_read_only=on', 'grepmind_5c_qa_db',
      'psql', '-XAt', '-v', 'ON_ERROR_STOP=1', '-U', 'qa4d', '-d', 'grepmind_5c_qa', '-c', sql,
    ], { encoding: 'utf8' }).trim().split('\n').filter(Boolean);
    expect(lines, projection.title).toHaveLength(1);
    const expected: Record<string, string | number> = JSON.parse(lines[0]);
    const { data: actual } = await response.json();
    expect(actual).toEqual([expect.objectContaining(expected)]);

    const table = page.getByRole('table', { name: projection.title });
    for (const field of projection.display) {
      const value = expected[field];
      const displayed = typeof value === 'number'
        ? new Intl.NumberFormat('en-IN', { style: 'currency', currency: String(expected.currency) }).format(value / 100)
        : value.replaceAll('_', ' ');
      await expect(table.getByRole('cell', { name: displayed, exact: true })).toBeVisible();
    }
  }
  await page.screenshot({ path: testInfo.outputPath('finance-overview-populated.png'), fullPage: true });
});
