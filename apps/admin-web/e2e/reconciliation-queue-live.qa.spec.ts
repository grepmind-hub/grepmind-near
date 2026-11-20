import { execFileSync } from 'node:child_process';
import { expect, test } from '@playwright/test';
import { readQaOtp } from './qa-otp';

test('finance Admin can open Payment Tracking from the live reconciliation queue', async ({ page, baseURL }, testInfo) => {
  test.skip(
    baseURL !== 'http://127.0.0.1:18305' || !process.env.QA_OTP_RUN_ID?.startsWith('phase5e-'),
    'Requires the dedicated disposable payment reconciliation QA stack.',
  );
  const sql = `
    SELECT json_agg(row_to_json(fixture) ORDER BY fixture.recorded_at DESC, fixture.id DESC)
    FROM (
      SELECT e.id::text, o.id::text order_id, o.reference_code,
             a.id::text attempt_id, a.status attempt_status, a.attempt_number,
             a.amount_minor, a.currency, e.outcome, e.created_at AS recorded_at
      FROM payment_reconciliation_events e
      JOIN payment_attempts a ON a.id=e.payment_attempt_id
      JOIN payment_intents i ON i.id=a.payment_intent_id
      JOIN customer_orders o ON o.id=i.order_id
      WHERE e.outcome='amount_mismatch'
    ) AS fixture
  `;
  type Exception = {
    id: string; order_id: string; reference_code: string; attempt_id: string;
    attempt_status: string; attempt_number: number; amount_minor: number; currency: string; outcome: string;
  };
  const fixtures: Exception[] = JSON.parse(execFileSync('docker', [
    'exec', '-e', 'PGOPTIONS=-c default_transaction_read_only=on', 'grepmind_5c_qa_db',
    'psql', '-XAt', '-v', 'ON_ERROR_STOP=1', '-U', 'qa4d', '-d', 'grepmind_5c_qa', '-c', sql,
  ], { encoding: 'utf8' }));
  expect(fixtures).toHaveLength(2);
  const outstanding = fixtures.find((entry) => entry.attempt_status === 'reconciliation_required');
  const resolved = fixtures.find((entry) => entry.attempt_status === 'succeeded');
  expect(outstanding).toBeDefined();
  expect(resolved).toBeDefined();
  if (!outstanding || !resolved) throw new Error('Expected a current and a historical exception');

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

  const queueRead = page.waitForResponse((response) =>
    new URL(response.url()).pathname.endsWith('/admin/payments/reconciliation-queue') && response.request().method() === 'GET',
  );
  await page.getByRole('button', { name: /Reconciliation queue/ }).click();
  const response = await queueRead;
  expect(response.status()).toBe(200);
  expect(response.headers()['cache-control']).toBe('no-store');
  const queue = await response.json();
  expect(queue.more_results).toBe(false);
  expect(queue.data).toHaveLength(1);
  expect(queue.data[0]).toMatchObject({
    id: outstanding.attempt_id, order_id: outstanding.order_id, attempt_id: outstanding.attempt_id,
    attempt_status: 'reconciliation_required', amount_minor: outstanding.amount_minor, kind: 'action_required',
    outcome: outstanding.outcome,
  });

  const table = page.getByRole('table', { name: 'Needs action' });
  const actionRow = table.getByRole('row').filter({ hasText: outstanding.reference_code });
  await expect(actionRow.getByRole('link', { name: outstanding.reference_code })).toBeVisible();
  await page.getByRole('button', { name: 'Recorded history', exact: true }).click();
  const historicalRow = page.getByRole('table', { name: 'Recorded history' }).getByRole('row').filter({ hasText: resolved.reference_code });
  await expect(historicalRow).toContainText('amount mismatch');
  await expect(historicalRow).toContainText('succeeded');
  await page.getByRole('button', { name: 'Needs action', exact: true }).click();
  await page.screenshot({ path: testInfo.outputPath('reconciliation-queue.png'), fullPage: true });

  const detailsRead = page.waitForResponse((item) =>
    item.url().endsWith(`/admin/payments/orders/${outstanding.order_id}`) && item.request().method() === 'GET',
  );
  await actionRow.getByRole('link', { name: outstanding.reference_code }).click();
  expect((await detailsRead).status()).toBe(200);
  await expect(page.getByRole('heading', { name: 'Payment tracking' })).toBeVisible();
  await expect(page.getByRole('heading', { name: outstanding.reference_code })).toBeVisible();
  await expect(page.getByRole('table', { name: 'Payment attempts' })).toContainText('reconciliation required');
  await expect(page.getByRole('table', { name: 'Reconciliation history' })).toContainText('amount mismatch');
});
