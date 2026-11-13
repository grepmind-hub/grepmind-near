#!/usr/bin/env node

// Live portal acceptance helper for an isolated Phase 3G-D QA stack.
// OTPs are read from the local development UI, held only in memory, and never logged.
const { chromium } = require('../../apps/admin-web/node_modules/playwright');
const fs = require('node:fs');
const path = require('node:path');
const { execFileSync } = require('node:child_process');

const action = process.argv[2];
const reference = process.env.PHASE3GD_ORDER_REF;
const adminPhone = process.env.PHASE3GD_ADMIN_PHONE;
const adminPhoneB = process.env.PHASE3GD_ADMIN_PHONE_B;
const merchantPhone = process.env.PHASE3GD_MERCHANT_PHONE;
const adminURL = process.env.PHASE3GD_ADMIN_URL || 'http://127.0.0.1:3312/admin/login';
const merchantURL = process.env.PHASE3GD_MERCHANT_URL || 'http://127.0.0.1:3313/';
const evidenceDir = process.env.PHASE3GD_EVIDENCE_DIR || path.resolve(__dirname, '../../docs/phases/evidence/phase3gd-final');

function required(value, label) {
  if (!value) throw new Error(`${label} is required.`);
  return value;
}

async function localCode(page, selector) {
  const text = await page.locator(selector).innerText({ timeout: 10000 });
  const match = text.match(/(?:Local development (?:OTP|code):?\s*)(\d{6})/i);
  if (!match) throw new Error('Local QA code was not visible in the expected development UI.');
  return match[1];
}

async function signInMerchant(page) {
  page.on('response', (response) => {
    if (response.url().includes('/auth/otp/request')) page.__otpRequestStatus = response.status();
  });
  await page.goto(merchantURL, { waitUntil: 'domcontentloaded' });
  await page.locator('input[type="tel"]').fill(required(merchantPhone, 'PHASE3GD_MERCHANT_PHONE'));
  await page.getByRole('button', { name: 'Get Verification Code' }).click();
  let code;
  try { code = await localCode(page, '[role="status"]'); }
  catch {
    const alertText = await page.locator('[role="alert"]').allInnerTexts().catch(() => []);
    console.error(`merchant_otp_request_failed=${JSON.stringify({ http_status: page.__otpRequestStatus ?? null, alerts: alertText.map((s) => s.replace(/[+]?\d[\d\s-]{4,}/g, '[redacted]')) })}`);
    throw new Error('Merchant local OTP was not available from the authentication UI.');
  }
  for (let i = 0; i < 6; i++) await page.locator(`#otp-${i}`).fill(code[i]);
  await page.getByRole('button', { name: 'Verify & Access Workspace' }).click();
  try {
    await page.getByRole('button', { name: 'Platform Orders' }).waitFor({ timeout: 20000 });
  } catch {
    const alertCount = await page.locator('[role="alert"]').count();
    const alertText = await page.locator('[role="alert"]').allInnerTexts().catch(() => []);
    const markers = [];
    for (const marker of ['Dashboard Overview', 'Platform Orders', 'Enter Your Mobile Number', 'Get Verification Code', 'Could not load', 'Unable to load']) {
      if (await page.getByText(marker, { exact: false }).first().isVisible().catch(() => false)) markers.push(marker);
    }
    console.error(`merchant_login_incomplete=${JSON.stringify({ url: new URL(page.url()).pathname, alert_count: alertCount, alert_text: alertText.map((s) => s.replace(/[+]?\d[\d\s-]{4,}/g, '[redacted]')), markers })}`);
    throw new Error('Authenticated Merchant workspace navigation did not become available.');
  }
  await page.getByRole('button', { name: 'Platform Orders' }).click();
  await page.getByRole('heading', { name: 'Assigned orders' }).waitFor({ timeout: 15000 });
}

async function signInAdmin(page) {
  await page.goto(adminURL, { waitUntil: 'domcontentloaded' });
  await page.getByLabel('Administrator mobile number').fill(required(process.env.PHASE3GD_ADMIN_PHONE || adminPhone, 'PHASE3GD_ADMIN_PHONE'));
  await page.getByRole('button', { name: /Continue securely/ }).click();
  const code = await localCode(page, 'p:has-text("Local development code:")');
  await page.getByLabel('Six-digit verification code').fill(code);
  await page.getByRole('button', { name: /Verify and continue/ }).click();
  try { await page.getByRole('button', { name: 'Delivery Dispatch' }).waitFor({ timeout: 20000 }); }
  catch {
    const alerts = await page.locator('[role="alert"]').allInnerTexts().catch(() => []);
    const text = await page.locator('body').innerText().catch(() => '');
    console.error(`admin_login_incomplete=${JSON.stringify({ url: new URL(page.url()).pathname, alerts: alerts.map((s) => s.replace(/[+]?[0-9][0-9\\s-]{4,}/g, '[redacted]')), hasDashboard: text.includes('Dashboard') })}`);
    throw new Error('Authenticated Admin workspace navigation did not become available.');
  }
  await page.getByRole('button', { name: 'Delivery Dispatch' }).click();
  await page.getByRole('heading', { name: 'Dispatch board' }).waitFor({ timeout: 20000 });
}

async function merchantStart(page) {
  await signInMerchant(page);
  const target = page.getByText(required(reference, 'PHASE3GD_ORDER_REF'), { exact: false }).first();
  await target.waitFor({ timeout: 20000 });
  // Order cards are intentionally collapsed by default; expand the exact
  // matching order before locating its state-transition controls.
  await target.click();
  await page.getByRole('button', { name: 'Accept order' }).click();
  await page.getByRole('button', { name: 'Start preparation' }).waitFor({ timeout: 15000 });
  await page.getByRole('button', { name: 'Start preparation' }).click();
  await page.getByRole('button', { name: 'Mark ready for pickup' }).waitFor({ timeout: 15000 });
  await page.getByRole('button', { name: 'Mark ready for pickup' }).click();
  await page.getByText('ready_for_pickup', { exact: false }).waitFor({ timeout: 15000 });
  fs.mkdirSync(evidenceDir, { recursive: true });
  await page.screenshot({ path: path.join(evidenceDir, 'merchant-order-ready.png'), fullPage: true });
  console.log(`merchant_order_ready=${reference}`);
}

async function merchantPickup(page) {
  await signInMerchant(page);
  const target = page.getByText(required(reference, 'PHASE3GD_ORDER_REF'), { exact: false }).first();
  await target.waitFor({ timeout: 20000 });
  await target.click();
  const issue = page.getByRole('button', { name: 'Issue pickup code' });
  await issue.waitFor({ timeout: 20000 });
  await issue.click();
  const dialog = page.getByRole('dialog', { name: 'Partner-to-rider handover' });
  await dialog.waitFor({ timeout: 10000 });
  const code = (await dialog.locator('p.font-mono.text-4xl').innerText()).trim();
  if (!/^\d{8}$/.test(code)) throw new Error('Merchant UI did not present a valid short-lived pickup code.');
  console.log('merchant_pickup_code_issued=true; code_redacted=true');
  const serial = process.env.PHASE3GD_RIDER_SERIAL || 'emulator-5558';
  const adb = process.env.PHASE3GD_ADB || '/mnt/d/emulator/android-sdk/platform-tools/adb.exe';
  // Transfer the short-lived code directly between the two local QA UIs. It
  // is never printed, persisted, or included in screenshot evidence.
  execFileSync(adb, ['-s', serial, 'shell', 'input', 'text', code], { stdio: 'ignore', timeout: 10000 });
  console.log('rider_code_entered=true; code_redacted=true');
  await new Promise((resolve) => setTimeout(resolve, 400));
  const size = execFileSync(adb, ['-s', serial, 'shell', 'wm', 'size'], { encoding: 'utf8', timeout: 10000 });
  const dimensions = size.match(/Physical size:\s*(\d+)x(\d+)/);
  if (!dimensions) throw new Error('Could not determine Rider emulator dimensions for the visible Verify button.');
  const x = Math.round(Number(dimensions[1]) * 0.681);
  // AlertDialog is vertically centered in the space above the software
  // keyboard; the Verify button is at roughly 42% of the full screen height.
  const y = Math.round(Number(dimensions[2]) * 0.42);
  execFileSync(adb, ['-s', serial, 'shell', 'input', 'tap', String(x), String(y)], { stdio: 'ignore', timeout: 10000 });
  console.log('rider_verify_tapped=true');
  await dialog.waitFor({ state: 'detached', timeout: 12000 }).catch(() => undefined);
  await page.getByRole('button', { name: 'Close and clear code' }).click().catch(() => undefined);
  await page.waitForFunction(() => document.body.innerText.toLowerCase().includes('picked up'), null, { timeout: 30000 });
  fs.mkdirSync(evidenceDir, { recursive: true });
  await page.screenshot({ path: path.join(evidenceDir, 'merchant-pickup-confirmed.png'), fullPage: true });
  console.log(`merchant_pickup_verified=${reference}; rider_ui_serial=${serial}`);
}

async function merchantReturn(page) {
  await signInMerchant(page);
  const target = page.getByText(required(reference, 'PHASE3GD_ORDER_REF'), { exact: false }).first();
  await target.waitFor({ timeout: 20000 });
  await target.click();
  const confirm = page.getByRole('button', { name: 'Confirm return handover' });
  await confirm.waitFor({ timeout: 30000 });
  await confirm.click();
  await page.getByText(/return receipt recorded/i).waitFor({ timeout: 15000 });
  const kind = page.getByLabel('Inventory disposition');
  await kind.selectOption('not_restockable');
  await page.getByLabel('Inspection reason').fill('Synthetic QA inspection: package is not eligible for restocking after the simulated vehicle issue and return.');
  await page.getByRole('button', { name: 'Submit inspected disposition' }).click();
  await page.getByText(/inventory inspection required/i).waitFor({ timeout: 15000 }).catch(() => undefined);
  fs.mkdirSync(evidenceDir, { recursive: true });
  await page.screenshot({ path: path.join(evidenceDir, 'merchant-return-receipt.png'), fullPage: true });
  console.log(`merchant_return_receipt=${reference}; disposition=not_restockable`);
}

async function adminReady(page) {
  const apiStatuses = [];
  page.on('response', (response) => {
    if (response.url().includes('/api/v1/admin/delivery-jobs')) apiStatuses.push(response.status());
  });
  await signInAdmin(page);
  await page.getByText(required(reference, 'PHASE3GD_ORDER_REF'), { exact: false }).waitFor({ timeout: 20000 });
  if (!apiStatuses.includes(200)) throw new Error('Admin Dispatch board did not receive a successful API-backed delivery-jobs response.');
  fs.mkdirSync(evidenceDir, { recursive: true });
  await page.screenshot({ path: path.join(evidenceDir, 'admin-dispatch-ready.png'), fullPage: true });
  console.log(`admin_dispatch_ready=${reference}; delivery_jobs_http=200`);
}

async function adminRetry(page) {
  const retryResponses = [];
  page.on('response', (response) => {
    if (response.url().includes('/delivery-jobs/') && response.url().endsWith('/retry')) retryResponses.push(response.status());
  });
  await signInAdmin(page);
  const card = page.locator('article[data-order-id]').filter({ hasText: required(reference, 'PHASE3GD_ORDER_REF') }).first();
  await card.waitFor({ timeout: 20000 });
  if (await card.getByRole('button', { name: 'Retry dispatch' }).count() === 0) {
    console.error(`admin_retry_unavailable=${JSON.stringify({ card: (await card.innerText()).slice(0, 900) })}`);
    throw new Error('Exact order is visible, but the Admin UI does not offer Retry dispatch in its current state.');
  }
  await card.locator('textarea').fill('Controlled isolated QA dispatch recovery after rider availability was confirmed.');
  await card.getByRole('button', { name: 'Retry dispatch' }).click();
  const dialog = page.getByRole('alertdialog');
  await dialog.waitFor({ timeout: 10000 });
  await dialog.getByRole('textbox').fill('Controlled isolated QA dispatch recovery after rider availability was confirmed.');
  await dialog.locator('input').fill(reference);
  await dialog.getByRole('button', { name: 'Confirm exact target' }).click();
  await page.waitForFunction(() => document.body.innerText.includes('offered'), null, { timeout: 15000 }).catch(() => undefined);
  if (!retryResponses.some((status) => status >= 200 && status < 300)) throw new Error(`Admin retry did not receive a successful API response (${retryResponses.join(',') || 'none'}).`);
  fs.mkdirSync(evidenceDir, { recursive: true });
  await page.screenshot({ path: path.join(evidenceDir, 'admin-dispatch-retried.png'), fullPage: true });
  console.log(`admin_dispatch_retry=${reference}; http=${retryResponses.at(-1)}`);
}

async function adminRequireReturn(page) {
  const resolutions = [];
  page.on('response', (response) => {
    if (response.url().includes('/exceptions/') && response.url().endsWith('/resolve')) resolutions.push(response.status());
  });
  await signInAdmin(page);
  const card = page.locator('article').filter({ hasText: required(reference, 'PHASE3GD_ORDER_REF') }).filter({ has: page.getByRole('button', { name: 'Require return' }) }).first();
  await card.waitFor({ timeout: 20000 });
  await card.getByRole('button', { name: 'Require return' }).click();
  const dialog = page.getByRole('alertdialog');
  await dialog.waitFor({ timeout: 10000 });
  await dialog.locator('textarea').fill('Verified pickup is complete. Rider reports a vehicle issue; retain custody and return the package to the assigned partner.');
  await dialog.locator('input').fill(reference);
  await dialog.getByRole('button', { name: 'Confirm action' }).click();
  await page.getByText('return required', { exact: false }).waitFor({ timeout: 15000 });
  if (!resolutions.some((status) => status >= 200 && status < 300)) throw new Error(`Require Return did not receive a successful API response (${resolutions.join(',') || 'none'}).`);
  fs.mkdirSync(evidenceDir, { recursive: true });
  await page.screenshot({ path: path.join(evidenceDir, 'admin-require-return.png'), fullPage: true });
  console.log(`admin_require_return=${reference}; http=${resolutions.at(-1)}`);
}

async function adminFinalizeReturn(page) {
  const finalizations = [];
  page.on('response', (response) => {
    if (response.url().includes('/delivery-jobs/') && response.url().endsWith('/recovery')) finalizations.push(response.status());
  });
  await signInAdmin(page);
  const card = page.locator('article[data-recovery-case]').filter({ hasText: required(reference, 'PHASE3GD_ORDER_REF') }).filter({ hasText: /return disposition pending/i }).first();
  await card.waitFor({ timeout: 30000 });
  if (await card.getByRole('button', { name: 'Finalize inspected return' }).count() === 0) {
    console.error(`admin_finalize_unavailable=${JSON.stringify({ card: (await card.innerText()).slice(0, 1000), buttons: await card.getByRole('button').allInnerTexts() })}`);
    throw new Error('The Admin recovery case is visible, but finalization is not enabled by its current data.');
  }
  await card.getByRole('button', { name: 'Finalize inspected return' }).click();
  const dialog = page.getByRole('alertdialog');
  await dialog.waitFor({ timeout: 10000 });
  await dialog.locator('textarea').fill('QA final review: merchant receipt and not-restockable inspection are recorded; close returned delivery without rider earnings.');
  await dialog.locator('input').fill(reference);
  await dialog.getByRole('button', { name: 'Confirm recovery' }).click();
  await page.waitForFunction(() => document.body.innerText.includes('No unresolved delivery alerts') || document.body.innerText.includes('return finalized'), null, { timeout: 20000 }).catch(() => undefined);
  if (!finalizations.some((status) => status >= 200 && status < 300)) throw new Error(`Admin return finalization did not receive a successful API response (${finalizations.join(',') || 'none'}).`);
  fs.mkdirSync(evidenceDir, { recursive: true });
  await page.screenshot({ path: path.join(evidenceDir, 'admin-return-finalized.png'), fullPage: true });
  console.log(`admin_return_finalized=${reference}; http=${finalizations.at(-1)}`);
}

async function main() {
  if (!['merchant-start', 'merchant-pickup', 'merchant-return', 'admin-ready', 'admin-retry', 'admin-require-return', 'admin-finalize-return'].includes(action)) {
    throw new Error('Usage: phase3gd_portal_acceptance.cjs merchant-start|merchant-pickup|merchant-return|admin-ready|admin-retry|admin-require-return|admin-finalize-return');
  }
  const browser = await chromium.launch({ headless: true });
  try {
    const page = await browser.newPage({ viewport: { width: 1440, height: 1000 } });
    page.setDefaultTimeout(15000);
    if (action === 'merchant-start') await merchantStart(page);
    else if (action === 'merchant-pickup') await merchantPickup(page);
    else if (action === 'merchant-return') await merchantReturn(page);
    else if (action === 'admin-retry') await adminRetry(page);
    else if (action === 'admin-require-return') {
      if (adminPhoneB) process.env.PHASE3GD_ADMIN_PHONE = adminPhoneB;
      await adminRequireReturn(page);
    } else if (action === 'admin-finalize-return') {
      if (adminPhoneB) process.env.PHASE3GD_ADMIN_PHONE = adminPhoneB;
      await adminFinalizeReturn(page);
    }
    else await adminReady(page);
  } finally {
    await browser.close();
  }
}

main().catch((error) => {
  console.error(`portal_acceptance_failed=${error.message}`);
  process.exitCode = 1;
});
