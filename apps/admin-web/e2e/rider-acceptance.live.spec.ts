import { test, expect, type Page } from '@playwright/test';
import { readQaOtp } from './qa-otp';

const primaryAdmin = process.env.PHASE3B_QA_PRIMARY_ADMIN_PHONE;
const regularAdmin = process.env.PHASE3B_QA_REGULAR_ADMIN_PHONE;
const riderPhone = process.env.PHASE3B_QA_RIDER_PHONE;
const requirementCode = 'qa_vehicle_photo_phase3b';

async function signIn(page: Page, phone: string) {
  await page.goto('/admin/login');
  const otpRequest = page.waitForResponse((response) =>
    response.url().endsWith('/auth/otp/request') && response.request().method() === 'POST');
  await page.getByLabel('Administrator mobile number').fill(phone);
  await page.getByRole('button', { name: 'Continue securely' }).click();
  const response = await otpRequest;
  expect(response.status()).toBe(202);
  const payload = (await response.json())?.data;
  expect(payload?.otp_code).toBeUndefined();
  await page.getByLabel('Six-digit verification code').fill(await readQaOtp(payload.challenge_id, phone, payload.expires_at));
  const verified = page.waitForResponse((r) =>
    r.url().endsWith('/auth/otp/verify') && r.request().method() === 'POST');
  await page.getByRole('button', { name: 'Verify and continue' }).click();
  expect((await verified).status()).toBe(200);
  await expect(page).toHaveURL(/\/admin\/dashboard$/);
}

test('live QA rider checklist is primary-superadmin protected', async ({ browser }) => {
  test.skip(!primaryAdmin || !regularAdmin || !riderPhone, 'Set the disposable Phase 3B QA primary-admin, regular-admin, and rider phone variables.');

  const primary = await browser.newPage();
  await signIn(primary, primaryAdmin!);
  await primary.getByRole('button', { name: /Rider Management/ }).click();
  await expect(primary.getByRole('heading', { name: 'Rider management' })).toBeVisible();
  await primary.getByPlaceholder('Requirement code').fill(requirementCode);
  await primary.getByPlaceholder('Display label').fill('QA-only vehicle image');
  await primary.getByRole('combobox').last().selectOption('two_wheeler');
  await primary.getByRole('checkbox', { name: 'Required for selected vehicle' }).check();
  const allowedMutation = primary.waitForResponse((r) =>
    r.url().endsWith('/admin/rider-document-requirements') && r.request().method() === 'POST');
  await primary.getByRole('button', { name: 'Save verification rule' }).click();
  expect((await allowedMutation).status()).toBe(200);
  await expect(primary.getByText('QA-only vehicle image')).toBeVisible();
  await primary.screenshot({ path: '../../docs/phases/screenshots/phase3b-admin-checklist.png', fullPage: true });

  const regular = await browser.newPage();
  await signIn(regular, regularAdmin!);
  await regular.getByRole('button', { name: /Rider Management/ }).click();
  await regular.getByPlaceholder('Requirement code').fill('qa_forbidden_requirement');
  await regular.getByPlaceholder('Display label').fill('QA forbidden mutation');
  const deniedMutation = regular.waitForResponse((r) =>
    r.url().endsWith('/admin/rider-document-requirements') && r.request().method() === 'POST');
  await regular.getByRole('button', { name: 'Save verification rule' }).click();
  const denied = await deniedMutation;
  expect(denied.status()).toBe(403);
  await expect(regular.locator('div[role="alert"]').first()).toContainText(/primary superadmin/i);
  const checklist = await regular.evaluate(async () => {
    const token = sessionStorage.getItem('admin_access_token');
    const response = await fetch('/api/v1/admin/rider-document-requirements', {
      headers: { Authorization: `Bearer ${token}` },
    });
    return { status: response.status, payload: await response.json() };
  });
  expect(checklist.status).toBe(200);
  expect(JSON.stringify(checklist.payload)).toContain(requirementCode);
  expect(JSON.stringify(checklist.payload)).not.toContain('qa_forbidden_requirement');
  await regular.screenshot({ path: '../../docs/phases/screenshots/phase3b-admin-regular-admin-denied.png', fullPage: true });

  // Review the same rider application submitted through the Pixel 8 UI.
  await primary.getByLabel('Filter rider applications').selectOption('submitted');
  let applicant = primary.getByRole('button', { name: /QA sample rider/ });
  if (await applicant.count()) {
  await applicant.click();
  const review = primary.getByRole('dialog', { name: 'Rider application review' });
  await expect(review.getByText('Kuanpal, Cuttack')).toBeVisible();
  const documentCard = review.locator('div.rounded-lg.bg-slate-50.p-3').filter({ hasText: 'QA-only vehicle image' });
  await expect(documentCard).toContainText('pending');
  const privateContent = primary.waitForResponse((r) =>
    /\/admin\/rider-documents\/[^/]+\/content$/.test(new URL(r.url()).pathname) && r.request().method() === 'GET');
  await documentCard.getByRole('button', { name: 'View private file' }).click();
  const privateResponse = await privateContent;
  expect(privateResponse.status()).toBe(200);
  expect(privateResponse.headers()['content-type']).toContain('image/png');
  const acceptedDocument = primary.waitForResponse((r) =>
    /\/admin\/rider-documents\/[^/]+\/review$/.test(new URL(r.url()).pathname) && r.request().method() === 'POST');
  await documentCard.getByRole('button').nth(1).click();
  expect((await acceptedDocument).status()).toBe(200);
  const approve = primary.waitForResponse((r) =>
    /\/admin\/rider-applications\/[^/]+\/review$/.test(new URL(r.url()).pathname) && r.request().method() === 'POST');
  await review.getByRole('button', { name: /Approve & grant requested areas/ }).click();
  expect((await approve).status()).toBe(200);
  } else {
    // Supports resuming a QA run if approval succeeded before a later assertion failed.
    await primary.getByLabel('Filter rider applications').selectOption('approved');
    applicant = primary.getByRole('button', { name: /QA sample rider/ });
    await expect(applicant).toBeVisible();
  }

  // Obtain a second short-lived test session in memory only. Suspension must
  // deny this already-issued access token on a protected Rider API request.
  const otpRequest = await primary.request.post('/api/v1/auth/otp/request', { data: { phone_e164: riderPhone } });
  expect(otpRequest.status()).toBe(202);
  const otpPayload = (await otpRequest.json())?.data;
  expect(otpPayload?.otp_code).toBeUndefined();
  const otp = await readQaOtp(otpPayload.challenge_id, riderPhone!, otpPayload.expires_at);
  const riderLogin = await primary.request.post('/api/v1/auth/otp/verify', { data: { phone_e164: riderPhone, otp_code: otp, challenge_id: otpPayload.challenge_id } });
  expect(riderLogin.status()).toBe(200);
  const accessToken = (await riderLogin.json())?.data?.access_token as string;
  expect(accessToken).toBeTruthy();
  const riderProfileBeforeSuspend = await primary.request.get('/api/v1/rider/profile', { headers: { Authorization: `Bearer ${accessToken}` } });
  expect(riderProfileBeforeSuspend.status()).toBe(200);

  await primary.getByLabel('Filter rider applications').selectOption('approved');
  await primary.getByRole('button', { name: /QA sample rider/ }).click();
  const suspend = primary.waitForResponse((r) =>
    /\/admin\/riders\/[^/]+\/suspend$/.test(new URL(r.url()).pathname) && r.request().method() === 'POST');
  primary.once('dialog', (dialog) => dialog.accept('QA-only access revocation check'));
  await primary.getByRole('dialog', { name: 'Rider application review' }).getByRole('button', { name: 'Suspend' }).click();
  expect((await suspend).status()).toBe(200);
  const riderProfileAfterSuspend = await primary.request.get('/api/v1/rider/profile', { headers: { Authorization: `Bearer ${accessToken}` } });
  expect([401, 403]).toContain(riderProfileAfterSuspend.status());

  if (process.env.PHASE3B_QA_HOLD_SUSPENDED === '1') {
    await primary.close();
    await regular.close();
    return;
  }

  await primary.getByLabel('Filter rider applications').selectOption('suspended');
  await primary.getByRole('button', { name: /QA sample rider/ }).click();
  const reactivate = primary.waitForResponse((r) =>
    /\/admin\/riders\/[^/]+\/reactivate$/.test(new URL(r.url()).pathname) && r.request().method() === 'POST');
  await primary.getByRole('dialog', { name: 'Rider application review' }).getByRole('button', { name: 'Reactivate' }).click();
  expect((await reactivate).status()).toBe(200);

  await primary.close();
  await regular.close();
});

test('reactivates the QA rider after device-side suspension verification', async ({ browser }) => {
  test.skip(process.env.PHASE3B_QA_REACTIVATE_ONLY !== '1' || !primaryAdmin, 'Run only after device-side suspended-state validation.');
  const page = await browser.newPage();
  await signIn(page, primaryAdmin!);
  await page.getByRole('button', { name: /Rider Management/ }).click();
  await page.getByLabel('Filter rider applications').selectOption('suspended');
  await page.getByRole('button', { name: /QA sample rider/ }).click();
  const reactivate = page.waitForResponse((r) =>
    /\/admin\/riders\/[^/]+\/reactivate$/.test(new URL(r.url()).pathname) && r.request().method() === 'POST');
  await page.getByRole('dialog', { name: 'Rider application review' }).getByRole('button', { name: 'Reactivate' }).click();
  expect((await reactivate).status()).toBe(200);
  await page.close();
});
