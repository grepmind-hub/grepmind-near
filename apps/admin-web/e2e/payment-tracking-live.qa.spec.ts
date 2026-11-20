import { execFileSync } from 'node:child_process';
import { expect, test } from '@playwright/test';
import { readQaOtp } from './qa-otp';

function fixture(query: string) {
  return JSON.parse(execFileSync('docker', [
    'exec', '-e', 'PGOPTIONS=-c default_transaction_read_only=on', 'grepmind_5c_qa_db',
    'psql', '-XAt', '-v', 'ON_ERROR_STOP=1', '-U', 'qa4d', '-d', 'grepmind_5c_qa',
    '-c', `SELECT row_to_json(fixture) FROM (${query}) AS fixture`,
  ], { encoding: 'utf8' }).trim());
}

test('finance Admin can track a verified payment and its reconciliation by exact order', async ({ page, baseURL }, testInfo) => {
  test.skip(
    baseURL !== 'http://127.0.0.1:18305' || !process.env.QA_OTP_RUN_ID?.startsWith('phase5d-'),
    'Requires the dedicated disposable payment tracking QA stack.',
  );
  const paid = fixture(`
    SELECT o.id::text order_id, o.reference_code, o.payment_status,
           a.id::text attempt_id, a.status attempt_status, a.amount_minor, a.currency,
           e.id::text event_id, e.outcome, e.provider_status
    FROM customer_orders o
    JOIN payment_intents i ON i.order_id=o.id
    JOIN payment_attempts a ON a.payment_intent_id=i.id
    JOIN payment_reconciliation_events e ON e.payment_attempt_id=a.id
    WHERE o.payment_status='paid' AND a.status='succeeded' AND e.outcome='matched'
  `);
  const empty = fixture(`
    SELECT o.id::text, o.reference_code FROM customer_orders o
    WHERE o.payment_method='cash_on_delivery'
      AND NOT EXISTS (SELECT 1 FROM payment_intents i WHERE i.order_id=o.id)
  `);
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
  await page.getByRole('button', { name: /Payment tracking/ }).click();

  async function lookup(reference: string) {
    await page.getByLabel('Order reference or UUID').fill(reference);
    const read = page.waitForResponse((response) =>
      new URL(response.url()).pathname.endsWith(`/admin/payments/orders/${reference}`) &&
      response.request().method() === 'GET',
    );
    await page.getByRole('button', { name: 'Look up order' }).click();
    return read;
  }

  const capturedResponse = await lookup(paid.reference_code.toLowerCase());
  expect(capturedResponse.status()).toBe(200);
  expect(capturedResponse.headers()['cache-control']).toBe('no-store');
  const { data: captured } = await capturedResponse.json();
  expect(captured.order).toMatchObject({ id: paid.order_id, reference_code: paid.reference_code, payment_status: paid.payment_status });
  expect(captured.attempts).toEqual([expect.objectContaining({
    id: paid.attempt_id, status: paid.attempt_status, amount_minor: paid.amount_minor, currency: paid.currency,
  })]);
  expect(captured.reconciliation).toEqual([expect.objectContaining({
    id: paid.event_id, attempt_id: paid.attempt_id, outcome: paid.outcome, provider_status: paid.provider_status,
  })]);
  expect(captured.attempts[0]).not.toHaveProperty('provider_reference');
  expect(captured.attempts[0]).not.toHaveProperty('provider_idempotency_key');
  const amount = new Intl.NumberFormat('en-IN', { style: 'currency', currency: paid.currency }).format(paid.amount_minor / 100);
  await expect(page.getByRole('heading', { name: paid.reference_code })).toBeVisible();
  await expect(page.getByRole('table', { name: 'Payment attempts' })).toContainText(amount);
  await expect(page.getByRole('table', { name: 'Payment attempts' })).toContainText('succeeded');
  await expect(page.getByRole('table', { name: 'Reconciliation history' })).toContainText('matched');
  await page.screenshot({ path: testInfo.outputPath('payment-tracking.png'), fullPage: true });

  const emptyResponse = await lookup(empty.id);
  expect(emptyResponse.status()).toBe(200);
  const { data: noAttempt } = await emptyResponse.json();
  expect(noAttempt).toMatchObject({ order: { reference_code: empty.reference_code }, intent: null, attempts: [], reconciliation: [] });
  await expect(page.getByText('No payment attempts recorded for this order.')).toBeVisible();
  await expect(page.getByText('No reconciliation events recorded for this order.')).toBeVisible();

  expect((await lookup('GN-NOTFOUND')).status()).toBe(404);
  await expect(page.getByRole('alert').filter({ hasText: 'No order matches that reference.' })).toBeVisible();
});
