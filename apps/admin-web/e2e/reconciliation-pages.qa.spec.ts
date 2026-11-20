import { execFileSync } from 'node:child_process';
import { expect, test, type Page } from '@playwright/test';
import { readQaOtp } from './qa-otp';

async function signIn(page: Page, phone: string) {
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
  await expect(page).toHaveURL(/\/admin\/dashboard$/);
}

function reconciliationActionStatus(page: Page) {
  return page.evaluate(async () => {
    const token = sessionStorage.getItem('admin_access_token');
    const result = await fetch('/api/v1/admin/payments/attempts/00000000-0000-4000-8000-000000000001/reconcile', {
      method: 'POST', headers: { Authorization: `Bearer ${token}` },
    });
    return result.status;
  });
}

test('queue handles loading, empty, failure, and permission denial', async ({ page }) => {
  await page.addInitScript(() => sessionStorage.setItem('admin_access_token', 'mock-admin'));
  let status = 200;
  let release = () => {};
  const wait = new Promise<void>((resolve) => { release = resolve; });
  await page.route('**/api/v1/admin/**', async (route) => {
    const path = new URL(route.request().url()).pathname;
    if (path.endsWith('/payments/reconciliation-queue')) {
      await wait;
      return route.fulfill({ status, json: { data: [], meta: { view: 'needs_action', count: 0, has_more: false } } });
    }
    if (path.endsWith('/admin/trends')) return route.fulfill({ json: { data: { series: [], categories: [] } } });
    return route.fulfill({ json: { data: [] } });
  });
  await page.goto('/admin/dashboard');
  await page.getByRole('button', { name: /Reconciliation queue/ }).click();
  const queue = page.getByRole('region', { name: 'Payment reconciliation queue' });
  await expect(queue.getByRole('status')).toHaveText('Loading reconciliation records…');
  release();
  await expect(queue.getByText('No attempts requiring reconciliation match these filters.')).toBeVisible();
  status = 500;
  await queue.getByRole('button', { name: 'Refresh queue' }).click();
  await expect(queue.getByRole('alert')).toContainText('could not be loaded');
  status = 403;
  await queue.getByRole('button', { name: 'Refresh queue' }).click();
  await expect(queue.getByRole('alert')).toHaveText('Active Platform Admin access is required.');
});

test('linked queue history and filters paginate past 50 live records', async ({ page, baseURL }, testInfo) => {
  test.setTimeout(90_000);
  test.skip(baseURL !== 'http://127.0.0.1:18305' || !/^phase5p[23]-/.test(process.env.QA_OTP_RUN_ID ?? ''),
    'Requires a dedicated Phase 5P.2 or 5P.3 disposable QA stack.');
  const query = `
    SELECT json_agg(row_to_json(t) ORDER BY t.attempt_status)
    FROM (
      SELECT o.reference_code, a.id::text attempt_id, a.status attempt_status,
             a.attempt_number, min(e.created_at)::date::text AS day, count(*)::int count
      FROM payment_reconciliation_events e JOIN payment_attempts a ON a.id=e.payment_attempt_id
      JOIN payment_intents i ON i.id=a.payment_intent_id JOIN customer_orders o ON o.id=i.order_id
      WHERE e.outcome='amount_mismatch' GROUP BY o.reference_code,a.id,a.status,a.attempt_number
    ) t
  `;
  type Fixture = { reference_code: string; attempt_id: string; attempt_status: string; attempt_number: number; day: string; count: number };
  const records: Fixture[] = JSON.parse(execFileSync('docker', [
    'exec', '-e', 'PGOPTIONS=-c default_transaction_read_only=on', 'grepmind_5c_qa_db',
    'psql', '-XAt', '-v', 'ON_ERROR_STOP=1', '-U', 'qa4d', '-d', 'grepmind_5c_qa', '-c', query,
  ], { encoding: 'utf8' }));
  const active = records.find((row) => row.attempt_status === 'reconciliation_required');
  const resolved = records.find((row) => row.attempt_status === 'succeeded');
  const failed = records.find((row) => row.attempt_status === 'failed');
  if (!active || !resolved || !failed) throw new Error('Expected outstanding, succeeded and failed QA attempts');
  expect(resolved.reference_code).toBe(failed.reference_code);
  expect(resolved.attempt_id).not.toBe(failed.attempt_id);
  expect(resolved.count).toBe(53);

  await signIn(page, '+919990000191');
  expect(await reconciliationActionStatus(page)).toBe(403);

  const nextRead = () => page.waitForResponse((response) =>
    new URL(response.url()).pathname.endsWith('/admin/payments/reconciliation-queue'),
  );
  const actionRead = nextRead();
  await page.getByRole('button', { name: /Reconciliation queue/ }).click();
  expect((await (await actionRead).json()).data).toEqual([expect.objectContaining({ attempt_id: active.attempt_id })]);
  const actionTable = page.getByRole('table', { name: 'Needs action' });
  await expect(actionTable.getByRole('row')).toHaveCount(2);
  await expect(actionTable.getByRole('link', { name: active.reference_code })).toBeInViewport();
  await page.screenshot({ path: testInfo.outputPath('needs-action-desktop.png'), fullPage: true });

  const linked = nextRead();
  await actionTable.getByRole('button', { name: 'View history' }).click();
  const relatedResponse = await linked;
  expect(new URL(relatedResponse.url()).searchParams.get('attempt_id')).toBe(active.attempt_id);
  expect((await relatedResponse.json()).data).toEqual([expect.objectContaining({ attempt_id: active.attempt_id })]);
  await expect(page.getByText(`History for ${active.reference_code} · attempt #${active.attempt_number}`)).toBeVisible();
  await page.getByRole('button', { name: 'Show all history' }).click();

  await page.getByLabel('Order reference or UUID').fill(resolved.reference_code.toLowerCase());
  await page.getByLabel('Attempt status').selectOption('succeeded');
  await page.getByLabel('Outcome').selectOption('amount_mismatch');
  await page.getByLabel('From date (UTC)').fill(resolved.day);
  await page.getByLabel('To date (UTC)').fill(resolved.day);
  let pending = nextRead();
  await page.getByRole('button', { name: 'Apply filters' }).click();
  const seen = new Set<string>();
  for (const length of [20, 20, 13]) {
    const response = await pending;
    expect(response.status()).toBe(200);
    const params = new URL(response.url()).searchParams;
    expect(params.get('status')).toBe('succeeded');
    expect(params.get('outcome')).toBe('amount_mismatch');
    expect(params.get('reference')).toBe(resolved.reference_code.toLowerCase());
    expect(params.get('from')).toBe(resolved.day);
    expect(params.get('to')).toBe(resolved.day);
    const pageData = await response.json();
    expect(pageData.data).toHaveLength(length);
    for (const row of pageData.data) {
      expect(row.attempt_id).toBe(resolved.attempt_id);
      expect(seen.has(row.id)).toBe(false);
      seen.add(row.id);
    }
    if (pageData.meta.has_more) {
      pending = nextRead();
      await page.getByRole('button', { name: 'Next page' }).click();
    }
  }
  expect(seen.size).toBe(53);
  await expect(page.getByText('Page 3', { exact: true })).toBeVisible();
  await expect(page.getByRole('button', { name: 'Next page' })).toBeDisabled();
  const previous = nextRead();
  await page.getByRole('button', { name: 'Previous page' }).click();
  expect((await (await previous).json()).data).toHaveLength(20);

  await page.getByLabel('Outcome').selectOption('matched');
  await page.getByRole('button', { name: 'Apply filters' }).click();
  const history = page.getByRole('table', { name: 'Recorded history' });
  await expect(history.getByRole('row').filter({ hasText: 'matched' })).toContainText('Phase 5C grant requester');
  await page.setViewportSize({ width: 390, height: 844 });
  await expect(page.getByRole('heading', { name: 'Payment reconciliation queue' })).toBeVisible();
  await expect(page.getByRole('button', { name: 'Back to Admin dashboard' })).toBeVisible();
  await expect(page.getByRole('button', { name: 'Apply filters' })).toBeInViewport();
  await expect(history.getByRole('link', { name: resolved.reference_code })).toBeInViewport();
  await expect(page.getByText('Grepmind Near', { exact: true })).toBeInViewport();
  const scrollArea = page.getByRole('region', { name: 'Recorded history table scroll area' });
  expect(await scrollArea.evaluate((node) => node.scrollWidth > node.clientWidth)).toBe(true);
  await page.screenshot({ path: testInfo.outputPath('history-mobile.png'), fullPage: true });
  await history.getByRole('link', { name: resolved.reference_code }).click();
  await expect(page.getByRole('heading', { name: resolved.reference_code })).toBeVisible();
  await expect(page.getByRole('table', { name: 'Payment attempts' })).toContainText(/failed/i);
  await expect(page.getByRole('table', { name: 'Payment attempts' })).toContainText(/succeeded/i);
  if (!process.env.QA_OTP_RUN_ID?.startsWith('phase5p3-')) return;

  const attempts = page.getByRole('table', { name: 'Payment attempts' });
  const captured = attempts.getByRole('row').filter({ hasText: resolved.attempt_id });
  const unsuccessful = attempts.getByRole('row').filter({ hasText: failed.attempt_id });
  await expect(captured).toContainText('Posted');
  await expect(unsuccessful).toContainText('No posted capture');
  await expect(captured.getByText('Sandbox', { exact: true })).toBeVisible();
  expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBe(390);
  await page.screenshot({ path: testInfo.outputPath('payment-tracking-mobile.png'), fullPage: true });

  const relatedRead = nextRead();
  await captured.getByRole('button', { name: 'History for attempt #2' }).click();
  expect(new URL((await relatedRead).url()).searchParams.get('attempt_id')).toBe(resolved.attempt_id);
  await expect(page.getByText(`History for ${resolved.reference_code} · attempt #2`)).toBeVisible();
  await page.getByRole('button', { name: 'Back to payment tracking' }).click();
  await expect(page.getByRole('heading', { name: resolved.reference_code })).toBeVisible();

  await page.setViewportSize({ width: 1440, height: 1050 });
  await page.getByRole('button', { name: /Finance overview/i }).click();
  const refunds = page.getByRole('region', { name: 'Refunds' });
  const refund = refunds.getByRole('link', { name: /^GN-/ });
  const paidReference = (await refund.textContent())?.trim();
  if (!paidReference) throw new Error('Expected a populated refund order reference');
  await expect(refunds.getByText('Sandbox', { exact: true })).toBeVisible();
  await expect(page.getByRole('region', { name: 'COD remittances' }).getByText('Sandbox', { exact: true })).toBeVisible();
  await expect(page.getByRole('region', { name: 'Merchant settlement simulations' }).getByText('Simulated', { exact: true })).toBeVisible();
  await expect(page.getByRole('region', { name: 'Posted merchant payables' }).getByRole('link', { name: /^GN-/ })).toBeVisible();
  await page.screenshot({ path: testInfo.outputPath('finance-overview-desktop.png'), fullPage: true });
  await page.setViewportSize({ width: 390, height: 844 });
  expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBe(390);
  await page.screenshot({ path: testInfo.outputPath('finance-overview-mobile.png'), fullPage: true });
  await page.setViewportSize({ width: 1440, height: 1050 });

  await refund.click();
  await expect(page).toHaveURL(new RegExp(`/payment-tracking/${paidReference}\\?from=finance-overview`));
  await expect(page.getByRole('heading', { name: paidReference })).toBeVisible();
  await expect(page.getByRole('table', { name: 'Refunds' }).getByRole('row').filter({ hasText: '#1' })).toContainText('Sandbox');
  await page.screenshot({ path: testInfo.outputPath('payment-tracking-desktop.png'), fullPage: true });
  await page.getByRole('button', { name: 'Back to Finance Overview' }).click();
  await expect(page.getByLabel('Refund status')).toHaveValue('requested');
  await expect(refund).toBeVisible();
  await page.getByLabel('Refund status').selectOption('succeeded');
  const payable = page.getByRole('region', { name: 'Posted merchant payables' }).getByRole('link', { name: /^GN-/ });
  await payable.click();
  await expect(page.getByRole('heading', { name: 'Payment tracking' })).toBeVisible();
  await expect(page.getByText('No payment attempts recorded for this order.')).toBeVisible();
  await page.getByRole('button', { name: 'Back to Finance Overview' }).click();
  await expect(page.getByLabel('Refund status')).toHaveValue('succeeded');

  const postStatus = await page.evaluate(async () => {
    const token = sessionStorage.getItem('admin_access_token');
    const response = await fetch('/api/v1/admin/finance/orders/00000000-0000-4000-8000-000000000001/accrue-payable', {
      method: 'POST', headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' }, body: '{}',
    });
    return response.status;
  });
  expect(postStatus).toBe(403);

  await page.goto('/admin/dashboard/payment-tracking/GN-DOES-NOT-EXIST');
  await expect(page.getByText('No order matches that reference.', { exact: true })).toBeVisible();

});

test('privileged Admin retains existing reconciliation authorization while queue stays read-only', async ({ page, baseURL }) => {
  test.skip(baseURL !== 'http://127.0.0.1:18305' || !/^phase5p[23]-/.test(process.env.QA_OTP_RUN_ID ?? ''),
    'Requires a dedicated Phase 5P.2 or 5P.3 disposable QA stack.');
  await signIn(page, '+919990000192');
  await page.getByRole('button', { name: /Reconciliation queue/ }).click();
  const queue = page.getByRole('region', { name: 'Payment reconciliation queue' });
  await expect(queue.getByRole('table', { name: 'Needs action' })).toBeVisible();
  await expect(queue.getByRole('button', { name: 'View history' })).toBeVisible();
  await expect(queue.getByRole('button', { name: /approve|reconcile payment|post payable/i })).toHaveCount(0);
  // The request reaches the existing authorization gate, then stops on an absent attempt.
  expect(await reconciliationActionStatus(page)).toBe(404);
});
