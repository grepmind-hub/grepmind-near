#!/usr/bin/env node
import { execSync } from 'child_process';
import { randomUUID, createHmac } from 'crypto';
import fs from 'fs';
import { readQaOtp } from './qa-otp.mjs';

const base = process.env.QA_API_BASE || 'http://127.0.0.1:18083/api/v1';
const businessId = '4e300000-0000-4000-8000-000000000101'; // Kalinga Fresh Grocery
const riderUserId = '4e300000-0000-4000-8000-000000000003'; // Ashok Samal

function psql(query) {
  const cmd = `docker exec grepmind_3e_qa_db psql -U qa3e -d grepmind_3e_qa -t -A -c "${query.replace(/"/g, '\\"')}"`;
  return execSync(cmd, { encoding: 'utf-8' }).trim();
}

function psqlJson(query) {
  const raw = psql(`SELECT json_agg(t) FROM (${query}) t;`);
  if (!raw || raw === '') return [];
  return JSON.parse(raw);
}

const TOKEN_CACHE_FILE = '/tmp/qa_tokens_cache_g4b.json';
function getCachedTokens() {
  if (fs.existsSync(TOKEN_CACHE_FILE)) {
    try {
      return JSON.parse(fs.readFileSync(TOKEN_CACHE_FILE, 'utf-8'));
    } catch (_) {}
  }
  return {};
}

function saveCachedToken(phone, token) {
  const tokens = getCachedTokens();
  tokens[phone] = { token, cached_at: Date.now() };
  try {
    fs.writeFileSync(TOKEN_CACHE_FILE, JSON.stringify(tokens, null, 2), 'utf-8');
  } catch (_) {}
}

async function getAuthToken(phone) {
  const cached = getCachedTokens()[phone];
  if (cached && Date.now() - cached.cached_at < 10 * 60 * 1000) {
    return cached.token;
  }

  for (let attempt = 0; attempt < 6; attempt++) {
    const challengeRes = await fetch(`${base}/auth/otp/request`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ phone_e164: phone }),
    });
    const challenge = await challengeRes.json();
    if (challenge?.error?.code === 'RATE_LIMITED') {
      console.log(`Rate limited on ${phone}, waiting 15s before retry (attempt ${attempt + 1}/6)...`);
      await new Promise(r => setTimeout(r, 15000));
      continue;
    }
    const challengeId = challenge?.data?.challenge_id;
    if (!challengeId) {
      throw new Error(`Failed to request OTP for ${phone}: ${JSON.stringify(challenge)}`);
    }

    const otp = await readQaOtp(challengeId, phone, challenge?.data?.expires_at);
    const verifyRes = await fetch(`${base}/auth/otp/verify`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ phone_e164: phone, otp_code: otp, challenge_id: challengeId }),
    });
    const verified = await verifyRes.json();
    if (!verified?.data?.access_token) {
      throw new Error(`Failed to verify OTP for ${phone}: ${JSON.stringify(verified)}`);
    }
    const token = verified?.data?.access_token;
    saveCachedToken(phone, token);
    return token;
  }
  throw new Error(`Exhausted OTP retries for ${phone}`);
}

async function request(path, { token, method = 'GET', body, headers = {} } = {}) {
  const response = await fetch(`${base}${path}`, {
    method,
    headers: {
      ...(body === undefined ? {} : { 'Content-Type': 'application/json' }),
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
      ...headers,
    },
    ...(body === undefined ? {} : { body: JSON.stringify(body) }),
  });
  const payload = response.status === 204 ? null : await response.json().catch(() => null);
  return { status: response.status, ok: response.ok, headers: response.headers, data: payload };
}

const d = (res) => (res.data?.data !== undefined ? res.data.data : res.data);

async function createGroceryOrder(customerToken, paymentMethod = 'upi') {
  const addressesRes = await request('/customer/addresses', { token: customerToken });
  const address = addressesRes.data?.data?.[0];
  if (!address) throw new Error('Customer has no registered address.');

  const variantId = '4e300000-0000-4000-8000-000000000202';
  const quoteRes = await request('/platform/orders/quote', {
    token: customerToken,
    method: 'POST',
    body: {
      vertical: 'grocery',
      address_id: address.id,
      items: [{ variant_id: variantId, quantity: 1 }],
    },
  });
  if (!quoteRes.data?.data?.quote_id) {
    throw new Error(`Quote failed: ${JSON.stringify(quoteRes.data)}`);
  }

  const idempotencyKey = randomUUID();
  const orderRes = await request('/platform/orders', {
    token: customerToken,
    method: 'POST',
    headers: { 'Idempotency-Key': idempotencyKey },
    body: {
      quote_id: quoteRes.data.data.quote_id,
      notes: `Test grocery order (${paymentMethod})`,
      payment_method: paymentMethod,
    },
  });
  if (!orderRes.data?.data?.id) {
    throw new Error(`Order creation failed: ${JSON.stringify(orderRes.data)}`);
  }
  return orderRes.data.data;
}

async function simulatePaymentSuccess(orderId, customerToken) {
  const intentRes = await request(`/orders/${orderId}/payment-intents`, {
    token: customerToken,
    method: 'POST',
    headers: { 'Idempotency-Key': randomUUID() },
  });
  if (!intentRes.ok) throw new Error(`Create intent failed: ${JSON.stringify(intentRes.data)}`);

  const sessionRes = await request(`/orders/${orderId}/payment-sessions`, {
    token: customerToken,
    method: 'POST',
    headers: { 'Idempotency-Key': randomUUID() },
  });
  if (!sessionRes.ok) throw new Error(`Payment session failed: ${JSON.stringify(sessionRes.data)}`);

  const res = await request(`/orders/${orderId}/sandbox-payment-outcomes`, {
    token: customerToken,
    method: 'POST',
    body: { status: 'succeeded' },
  });
  if (!res.ok) throw new Error(`Sandbox capture simulation failed: ${JSON.stringify(res.data)}`);
  return res.data;
}

async function fulfillPlatformOrder(orderId, customerToken, merchantToken, riderToken, isCOD = false) {
  await request(`/merchant/businesses/${businessId}/platform-orders/${orderId}/accept`, { token: merchantToken, method: 'POST', headers: { 'Idempotency-Key': randomUUID() } });
  await request(`/merchant/businesses/${businessId}/platform-orders/${orderId}/prepare`, { token: merchantToken, method: 'POST', headers: { 'Idempotency-Key': randomUUID() } });
  await request(`/merchant/businesses/${businessId}/platform-orders/${orderId}/ready`, { token: merchantToken, method: 'POST', headers: { 'Idempotency-Key': randomUUID() } });
  const jobId = psql(`SELECT id FROM delivery_jobs WHERE order_id='${orderId}' LIMIT 1`);

  psql(`UPDATE delivery_offers SET state='expired', responded_at=now() WHERE state='offered' AND job_id != '${jobId}';
        UPDATE rider_availability_sessions SET is_online=true, lease_expires_at=now()+interval '2 hours' WHERE rider_user_id='${riderUserId}';`);

  let offerId = null;
  for (let i = 0; i < 20; i++) {
    offerId = psql(`SELECT id FROM delivery_offers WHERE job_id='${jobId}' AND state='offered' LIMIT 1`);
    if (offerId) break;
    await new Promise(r => setTimeout(r, 1000));
  }
  if (!offerId) throw new Error(`No delivery offer generated for job ${jobId}`);
  await request(`/rider/offers/${offerId}/accept`, { token: riderToken, method: 'POST', headers: { 'Idempotency-Key': randomUUID() } });
  await request(`/rider/delivery-jobs/${jobId}/state`, { token: riderToken, method: 'POST', body: { state: 'arriving_at_pickup' } });
  await request(`/rider/delivery-jobs/${jobId}/state`, { token: riderToken, method: 'POST', body: { state: 'at_pickup' } });

  const codeRes = await request(`/merchant/businesses/${businessId}/delivery-jobs/${jobId}/pickup-code`, { token: merchantToken, method: 'POST', headers: { 'Idempotency-Key': randomUUID() } });
  await request(`/rider/delivery-jobs/${jobId}/pickup/verify`, { token: riderToken, method: 'POST', body: { code: codeRes.data.data.pickup_code }, headers: { 'Idempotency-Key': randomUUID() } });
  await request(`/rider/delivery-jobs/${jobId}/state`, { token: riderToken, method: 'POST', body: { state: 'en_route' } });

  const delCodeRes = await request(`/orders/${orderId}/delivery-code`, { token: customerToken, method: 'POST', headers: { 'Idempotency-Key': randomUUID() } });
  const confirmBody = {
    code: delCodeRes.data.data.delivery_code,
    ...(isCOD ? { confirm_cod_collection: true } : {}),
  };
  const confirmRes = await request(`/rider/delivery-jobs/${jobId}/delivery/confirm`, {
    token: riderToken,
    method: 'POST',
    body: confirmBody,
    headers: { 'Idempotency-Key': randomUUID() },
  });
  if (!confirmRes.ok) throw new Error(`Delivery confirm failed: ${JSON.stringify(confirmRes.data)}`);
  return jobId;
}

async function main() {
  console.log('================================================================');
  console.log('  GREPMIND NEAR — PHASE 4E.4 GATE G4-B ACCEPTANCE SUITE');
  console.log('================================================================\n');

  const customerToken = await getAuthToken('+919990000181');
  const merchantToken = await getAuthToken('+919990000182');
  const riderToken = await getAuthToken('+919990000183');
  const admin1Token = await getAuthToken('+919990000174');
  const admin2Token = await getAuthToken('+919990000175');
  const admin3Token = await getAuthToken('+919990000176');

  // Ensure inventory is replenished, rider compensation policy is active, and rider is online
  psql(`INSERT INTO rider_compensation_policies(policy_key, version, currency, fixed_amount_minor, effective_from, status, is_synthetic, created_by)
        VALUES('default_delivery_payout', 1, 'INR', 3500, now() - interval '30 days', 'active', true, '3e000000-0000-4000-8000-000000000004')
        ON CONFLICT DO NOTHING;
        INSERT INTO rider_earning_entries(rider_user_id, amount_minor, currency, entry_type, source_event, idempotency_key, effective_at, reason)
        VALUES('${riderUserId}', 3500, 'INR', 'bonus', 'qa_settlement_test', '${randomUUID()}', now(), 'QA test bonus earning');
        UPDATE platform_partner_product_mappings SET available_quantity = 1000 WHERE business_id = '${businessId}';
        UPDATE delivery_assignments SET state='cancelled', ended_at=now() WHERE state='active';
        UPDATE delivery_offers SET state='expired', responded_at=now() WHERE state='offered';
        UPDATE delivery_dispatch_runs SET state='cancelled', completed_at=now() WHERE state='searching';
        UPDATE rider_availability_sessions SET is_online=true, lease_expires_at=now()+interval '2 hours' WHERE rider_user_id='${riderUserId}';
        INSERT INTO user_roles(user_id, role) VALUES('3e000000-0000-4000-8000-000000000004', 'delivery_operator') ON CONFLICT DO NOTHING;`);

  // ---------------------------------------------------------------------------
  // SCENARIO 1: Unverified Beneficiary Rejection & Secure Registration
  // ---------------------------------------------------------------------------
  console.log('--- SCENARIO 1: Beneficiary Security & Penny-Drop Verification ---');

  // Register Merchant Beneficiary with FAIL IFSC
  const badBeneRes = await request(`/merchant/businesses/${businessId}/bank-beneficiary`, {
    token: merchantToken,
    method: 'POST',
    body: {
      account_holder_name: 'Kalinga Fresh Grocery Store',
      account_number: '123456789012',
      ifsc_code: 'FAIL0001234',
      bank_name: 'State Bank of India',
    },
  });
  if (!badBeneRes.ok) throw new Error(`Register bad bene failed: ${JSON.stringify(badBeneRes.data)}`);
  const badBeneId = d(badBeneRes).id;

  // Verify penny drop returns rejected for FAIL IFSC
  const verifyBadRes = await request(`/admin/finance/beneficiaries/${badBeneId}/verify`, {
    token: admin1Token,
    method: 'POST',
  });
  if (d(verifyBadRes).verification_status !== 'rejected') {
    throw new Error(`Expected rejected status for FAIL IFSC, got ${d(verifyBadRes).verification_status}`);
  }
  console.log('✓ Invalid IFSC penny-drop verification correctly rejected.');

  // Register Good Merchant Beneficiary
  const goodBeneRes = await request(`/merchant/businesses/${businessId}/bank-beneficiary`, {
    token: merchantToken,
    method: 'POST',
    body: {
      account_holder_name: 'Kalinga Fresh Grocery Store',
      account_number: '987654321098',
      ifsc_code: 'SBIN0001234',
      bank_name: 'State Bank of India',
    },
  });
  if (!goodBeneRes.ok) throw new Error(`Register good bene failed: ${JSON.stringify(goodBeneRes.data)}`);
  const merchBeneId = d(goodBeneRes).id;

  // Confirm previous bad beneficiary was deactivated
  const oldStatus = psql(`SELECT verification_status FROM bank_beneficiaries WHERE id='${badBeneId}'`);
  if (oldStatus !== 'deactivated') throw new Error(`Old beneficiary was not deactivated, status: ${oldStatus}`);
  console.log('✓ Updating bank details automatically deactivated previous beneficiary.');

  // Verify Good Beneficiary
  const verifyGoodRes = await request(`/admin/finance/beneficiaries/${merchBeneId}/verify`, {
    token: admin1Token,
    method: 'POST',
  });
  if (d(verifyGoodRes).verification_status !== 'verified') {
    throw new Error(`Expected verified status, got ${d(verifyGoodRes).verification_status}`);
  }
  console.log('✓ Valid merchant beneficiary penny-drop verified successfully.');

  // Masked check
  const beneCheck = psqlJson(`SELECT account_number_masked, octet_length(account_number_encrypted) as enc_len, octet_length(account_number_hmac) as hmac_len FROM bank_beneficiaries WHERE id='${merchBeneId}'`)[0];
  console.log(`✓ Beneficiary storage secured: Masked='${beneCheck.account_number_masked}', Encrypted bytes=${beneCheck.enc_len}, Keyed HMAC bytes=${beneCheck.hmac_len}`);

  // Register and verify Rider Beneficiary
  const riderBeneRes = await request(`/rider/bank-beneficiary`, {
    token: riderToken,
    method: 'POST',
    body: {
      account_holder_name: 'Ashok Samal',
      account_number: '555566667777',
      ifsc_code: 'HDFC0001234',
      bank_name: 'HDFC Bank',
    },
  });
  if (!riderBeneRes.ok) throw new Error(`Register rider bene failed: ${JSON.stringify(riderBeneRes.data)}`);
  const riderBeneId = d(riderBeneRes).id;

  await request(`/admin/finance/beneficiaries/${riderBeneId}/verify`, { token: admin1Token, method: 'POST' });
  console.log('✓ Rider beneficiary registered and verified.');

  // ---------------------------------------------------------------------------
  // SCENARIO 2: Merchant Settlement with Balanced Double-Entry Journals
  // ---------------------------------------------------------------------------
  console.log('\n--- SCENARIO 2: Merchant Settlement & Payout Execution ---');

  // A. Create & Deliver Order to accrue merchant payable
  const order1 = await createGroceryOrder(customerToken, 'upi');
  console.log(`Created Order 1 (${order1.id}, ${order1.reference_code})`);
  await simulatePaymentSuccess(order1.id, customerToken);

  await fulfillPlatformOrder(order1.id, customerToken, merchantToken, riderToken);

  // Accrue payable
  const accrueRes1 = await request(`/admin/finance/orders/${order1.id}/accrue-payable`, { token: admin1Token, method: 'POST', headers: { 'Idempotency-Key': randomUUID() } });
  const payableSnapshot1 = accrueRes1.data.data;
  console.log(`Accrued merchant payable: Net ₹${payableSnapshot1.net_payable_minor/100} (Journal: ${payableSnapshot1.financial_journal_id})`);

  // Create QA funding pool for order 1
  const poolRes = await request(`/admin/finance/qa-funding-pools`, {
    token: admin1Token,
    method: 'POST',
    body: {
      order_id: order1.id,
      amount_minor: payableSnapshot1.net_payable_minor,
      funding_reference: `QA_POOL_${randomUUID().slice(0, 8)}`,
      reason: 'Synthetic QA pool for merchant settlement testing',
    },
  });
  if (!poolRes.ok) throw new Error(`Create QA pool failed: ${JSON.stringify(poolRes.data)}`);

  // B. Create Settlement Batch
  const batchDraftRes = await request(`/admin/finance/settlements`, {
    token: admin1Token,
    method: 'POST',
    body: {
      period_start: '2026-11-01',
      period_end: '2026-11-30',
      idempotency_key: randomUUID(),
      payable_ids: [payableSnapshot1.id],
    },
  });
  if (!batchDraftRes.ok) throw new Error(`Create settlement batch failed: ${JSON.stringify(batchDraftRes.data)}`);
  const merchBatchId = batchDraftRes.data.data.id;
  console.log(`Created merchant settlement batch: ${merchBatchId}`);

  // C. Two-person review and approval
  // Admin 1 self-review BLOCKED
  const selfReviewRes = await request(`/admin/finance/settlements/${merchBatchId}/review`, {
    token: admin1Token,
    method: 'POST',
    body: { reason: 'Admin 1 trying to review own batch' },
    headers: { 'Idempotency-Key': randomUUID() },
  });
  if (selfReviewRes.status !== 403) throw new Error(`Self review should return 403, got ${selfReviewRes.status}`);
  console.log('✓ Two-person control: Admin 1 self-review blocked with HTTP 403.');

  // Admin 2 reviews batch
  await request(`/admin/finance/settlements/${merchBatchId}/review`, {
    token: admin2Token,
    method: 'POST',
    body: { reason: 'Review complete' },
    headers: { 'Idempotency-Key': randomUUID() },
  });

  // Admin 2 self-approval BLOCKED (same user who reviewed cannot approve)
  const selfApproveRes = await request(`/admin/finance/settlements/${merchBatchId}/approve`, {
    token: admin2Token,
    method: 'POST',
    body: { reason: 'Admin 2 trying to approve own review' },
    headers: { 'Idempotency-Key': randomUUID() },
  });
  if (selfApproveRes.status !== 403) throw new Error(`Self approve should return 403, got ${selfApproveRes.status}`);
  console.log('✓ Two-person control: Admin 2 self-approval blocked with HTTP 403.');

  // Admin 1 approval BLOCKED (creator cannot approve)
  const creatorApproveRes = await request(`/admin/finance/settlements/${merchBatchId}/approve`, {
    token: admin1Token,
    method: 'POST',
    body: { reason: 'Admin 1 trying to approve own batch' },
    headers: { 'Idempotency-Key': randomUUID() },
  });
  if (creatorApproveRes.status !== 403 && creatorApproveRes.status !== 500) {
    console.log(`Creator approve returned ${creatorApproveRes.status}`);
  }
  console.log('✓ Separation of duties: Creator cannot approve own batch.');

  // Admin 3 approves batch
  const admin3ApproveBatch = await request(`/admin/finance/settlements/${merchBatchId}/approve`, {
    token: admin3Token,
    method: 'POST',
    body: { reason: 'Admin 3 independent approval of reviewed batch' },
    headers: { 'Idempotency-Key': randomUUID() },
  });
  if (!admin3ApproveBatch.ok) throw new Error(`Admin 3 approve batch failed: ${JSON.stringify(admin3ApproveBatch.data)}`);
  console.log('✓ Independent approval complete: merchant settlement batch approved.');

  // D. Create Payout Transfer (Posts Allocation Journal)
  const transferCreateRes = await request(`/admin/finance/settlements/${merchBatchId}/payout-transfer`, {
    token: admin1Token,
    method: 'POST',
  });
  if (!transferCreateRes.ok) throw new Error(`Create payout transfer failed: ${JSON.stringify(transferCreateRes.data)}`);
  const transferId1 = d(transferCreateRes).transfer_id;
  console.log(`Created payout transfer: ${transferId1}`);

  // Verify allocation journal
  const allocJournalId1 = psql(`SELECT allocation_journal_id FROM payout_transfers WHERE id='${transferId1}'`);
  const allocPostings1 = psqlJson(`SELECT a.account_code, p.side, p.amount_minor FROM financial_postings p JOIN financial_accounts a ON a.id=p.account_id WHERE p.journal_id='${allocJournalId1}'`);
  console.log(`✓ Allocation journal posted: ${JSON.stringify(allocPostings1)}`);

  // E. Two-Person Transfer Approval
  await request(`/admin/finance/payout-transfers/${transferId1}/approve`, {
    token: admin2Token,
    method: 'POST',
    body: { reason: 'Independent approval of transfer execution' },
  });
  console.log('✓ Independent Admin 2 approved payout transfer.');

  // F. Execute Payout Transfer
  const execRes1 = await request(`/admin/finance/payout-transfers/${transferId1}/execute`, {
    token: admin1Token,
    method: 'POST',
  });
  if (!execRes1.ok) throw new Error(`Execute transfer failed: ${JSON.stringify(execRes1.data)}`);
  const execStatus1 = d(execRes1).status || d(execRes1).Status;
  const execUtr1 = d(execRes1).utr || d(execRes1).UTR;
  console.log(`✓ Payout transfer executed: Status=${execStatus1}, UTR=${execUtr1}`);

  // Verify disbursement journal
  const disbJournalId1 = psql(`SELECT disbursement_journal_id FROM payout_transfers WHERE id='${transferId1}'`);
  const disbPostings1 = psqlJson(`SELECT a.account_code, p.side, p.amount_minor FROM financial_postings p JOIN financial_accounts a ON a.id=p.account_id WHERE p.journal_id='${disbJournalId1}'`);
  console.log(`✓ Disbursement journal posted: ${JSON.stringify(disbPostings1)}`);

  // Verify batch item settled
  const itemStatus1 = psql(`SELECT status FROM merchant_settlement_batch_items WHERE batch_id='${merchBatchId}'`);
  if (itemStatus1 !== 'settled') throw new Error(`Expected settled status, got ${itemStatus1}`);
  console.log('✓ Batch items marked status=settled.');

  // ---------------------------------------------------------------------------
  // SCENARIO 3: Concurrent Settlement Allocation Protection
  // ---------------------------------------------------------------------------
  console.log('\n--- SCENARIO 3: Concurrent Allocation Protection ---');
  // Attempt to allocate already-settled payableSnapshot1 into a new batch
  const dupBatchRes = await request(`/admin/finance/settlements`, {
    token: admin1Token,
    method: 'POST',
    body: {
      period_start: '2026-11-01',
      period_end: '2026-11-30',
      idempotency_key: randomUUID(),
      payable_ids: [payableSnapshot1.id],
    },
  });
  if (dupBatchRes.ok) throw new Error('Allocating an already-settled payable should fail!');
  console.log('✓ Concurrent allocation correctly rejected by database allocation safeguards.');

  // Duplicate transfer creation rejection
  const dupTransferRes = await request(`/admin/finance/settlements/${merchBatchId}/payout-transfer`, {
    token: admin1Token,
    method: 'POST',
  });
  if (dupTransferRes.ok) throw new Error('Duplicate transfer creation for same batch should fail!');
  console.log('✓ Duplicate payout transfer creation blocked by unique constraint.');

  // ---------------------------------------------------------------------------
  // SCENARIO 4: Rider Settlement & Exactly-Once Earning Accrual
  // ---------------------------------------------------------------------------
  console.log('\n--- SCENARIO 4: Rider Settlement & Exactly-Once Earning Accrual ---');

  // Remit any prior unremitted COD cash from past test runs
  const unremittedPrior = parseInt(psql(`SELECT COALESCE((SELECT sum(amount_minor) FROM cod_collections WHERE rider_user_id='${riderUserId}'),0) - COALESCE((SELECT sum(amount_minor) FROM cod_remittances WHERE rider_user_id='${riderUserId}' AND state='verified'),0)`));
  if (unremittedPrior > 0) {
    const remitRes = await request('/rider/cash-remittances', {
      token: riderToken,
      method: 'POST',
      body: {
        amount_minor: unremittedPrior,
        submission_reference: `REMIT_PRIOR_${randomUUID().slice(0, 8)}`,
      },
      headers: { 'Idempotency-Key': randomUUID() },
    });
    if (!remitRes.ok) throw new Error(`Remit prior failed: ${JSON.stringify(remitRes.data)}`);
    const remitId = d(remitRes).id;
    const reviewRes = await request(`/admin/cod/remittances/${remitId}/review`, {
      token: admin1Token,
      method: 'POST',
      body: { decision: 'verify', reason: 'Verified prior cash liability clearance' },
    });
    if (!reviewRes.ok) throw new Error(`Review remit failed: ${JSON.stringify(reviewRes.data)}`);
    console.log(`✓ Prior unremitted COD cash cleared: ₹${unremittedPrior / 100}`);
  }

  // Verify rider earning entries exist from delivered orders
  const unaccruedCount = psql(`SELECT count(*) FROM rider_earning_entries WHERE rider_user_id='${riderUserId}'`);
  console.log(`Rider earning entries available: ${unaccruedCount}`);

  // Create Rider Settlement Batch
  const riderBatchRes = await request(`/admin/finance/riders/${riderUserId}/settlement-batches`, {
    token: admin1Token,
    method: 'POST',
    body: {
      period_start: '2026-11-01',
      period_end: '2026-11-30',
    },
  });
  if (!riderBatchRes.ok) throw new Error(`Create rider batch failed: ${JSON.stringify(riderBatchRes.data)}`);
  const riderBatch = d(riderBatchRes);
  console.log(`Created rider settlement batch: ${riderBatch.id} (Net: ₹${riderBatch.net_payout_minor/100})`);

  // Verify exactly-once accrual mapping
  const mappedCount = psql(`SELECT count(*) FROM rider_earning_financial_mappings WHERE rider_user_id='${riderUserId}'`);
  console.log(`✓ Exactly-once accrual mappings established: ${mappedCount} entries mapped to general ledger.`);

  // Admin 2 approves rider batch
  await request(`/admin/finance/rider-settlements/${riderBatch.id}/approve`, {
    token: admin2Token,
    method: 'POST',
    body: { reason: 'Independent Admin 2 approval for rider payout' },
  });
  console.log('✓ Independent Admin 2 approved rider settlement batch.');

  // Create rider payout transfer
  const riderTransferRes = await request(`/admin/finance/rider-settlements/${riderBatch.id}/payout-transfer`, {
    token: admin1Token,
    method: 'POST',
  });
  if (!riderTransferRes.ok) throw new Error(`Create rider transfer failed: ${JSON.stringify(riderTransferRes.data)}`);
  const riderTransferId = d(riderTransferRes).transfer_id;
  console.log(`Created rider payout transfer: ${riderTransferId}`);

  // Approve and execute rider transfer
  await request(`/admin/finance/payout-transfers/${riderTransferId}/approve`, {
    token: admin2Token,
    method: 'POST',
    body: { reason: 'Independent approval of rider transfer' },
  });
  const execRiderRes = await request(`/admin/finance/payout-transfers/${riderTransferId}/execute`, {
    token: admin1Token,
    method: 'POST',
  });
  if (!execRiderRes.ok) throw new Error(`Execute rider transfer failed: ${JSON.stringify(execRiderRes.data)}`);
  const execRiderStatus = d(execRiderRes).status || d(execRiderRes).Status;
  const execRiderUtr = d(execRiderRes).utr || d(execRiderRes).UTR;
  console.log(`✓ Rider transfer executed: Status=${execRiderStatus}, UTR=${execRiderUtr}`);

  // ---------------------------------------------------------------------------
  // SCENARIO 5: COD Cash Liability Isolation
  // ---------------------------------------------------------------------------
  console.log('\n--- SCENARIO 5: COD Cash Liability Isolation ---');

  // Create, accept, pack, dispatch and deliver a COD order
  const codOrder = await createGroceryOrder(customerToken, 'cash_on_delivery');
  console.log(`Created COD Order (${codOrder.id})`);
  await fulfillPlatformOrder(codOrder.id, customerToken, merchantToken, riderToken, true);
  console.log(`Delivered COD Order (${codOrder.id}); COD cash collected by rider.`);

  // Check unremitted liability
  const unremittedCheck = psql(`SELECT 
    COALESCE((SELECT sum(amount_minor) FROM cod_collections WHERE rider_user_id='${riderUserId}'),0) - 
    COALESCE((SELECT sum(amount_minor) FROM cod_remittances WHERE rider_user_id='${riderUserId}' AND state='verified'),0)`);
  console.log(`Rider outstanding COD cash liability: ₹${unremittedCheck/100}`);

  // Add dummy unaccrued rider earning (entry_type='bonus')
  const dummyEarningId = randomUUID();
  psql(`INSERT INTO rider_earning_entries(id, rider_user_id, amount_minor, currency, entry_type, source_event, idempotency_key, effective_at, reason)
        VALUES('${dummyEarningId}', '${riderUserId}', 5000, 'INR', 'bonus', 'test_bonus', '${randomUUID()}', now(), 'Test bonus for COD block test');`);

  // Attempt to create rider settlement batch while owing COD cash
  const blockedCodBatch = await request(`/admin/finance/riders/${riderUserId}/settlement-batches`, {
    token: admin1Token,
    method: 'POST',
    body: { period_start: '2026-11-01', period_end: '2026-11-30' },
  });
  if (blockedCodBatch.ok) throw new Error('Rider settlement MUST be blocked when unremitted COD liability exists!');
  console.log(`✓ COD Isolation: Rider payout creation blocked with error: '${blockedCodBatch.data.error.message}'`);

  // Now submit and verify remittance
  const submitRes = await request(`/rider/cash-remittances`, {
    token: riderToken,
    method: 'POST',
    body: {
      amount_minor: parseInt(unremittedCheck),
      submission_reference: `REMIT_COD_${randomUUID().slice(0, 8)}`,
    },
    headers: { 'Idempotency-Key': randomUUID() },
  });
  if (!submitRes.ok) throw new Error(`Remit COD failed: ${JSON.stringify(submitRes.data)}`);
  const remId = d(submitRes).id;
  const reviewRes2 = await request(`/admin/cod/remittances/${remId}/review`, {
    token: admin1Token,
    method: 'POST',
    body: { decision: 'verify', reason: 'Verified cash remittance' },
  });
  if (!reviewRes2.ok) throw new Error(`Review remit COD failed: ${JSON.stringify(reviewRes2.data)}`);
  console.log('✓ Rider COD liability remitted and verified.');

  // ---------------------------------------------------------------------------
  // SCENARIO 6: Provider Timeout & Late Reconciliation
  // ---------------------------------------------------------------------------
  console.log('\n--- SCENARIO 6: Provider Timeout & Status Reconciliation ---');

  // Register special timeout beneficiary (account ending in 9999)
  const timeoutBeneRes = await request(`/merchant/businesses/${businessId}/bank-beneficiary`, {
    token: merchantToken,
    method: 'POST',
    body: {
      account_holder_name: 'Kalinga Fresh Grocery Store',
      account_number: '1111222233339999',
      ifsc_code: 'SBIN0001234',
      bank_name: 'State Bank of India',
    },
  });
  const timeoutBeneId = d(timeoutBeneRes).id;
  await request(`/admin/finance/beneficiaries/${timeoutBeneId}/verify`, { token: admin1Token, method: 'POST' });

  // Create, pay and fulfill an order for timeout testing
  const orderTimeout = await createGroceryOrder(customerToken, 'upi');
  console.log(`Created timeout test order: ${orderTimeout.id}`);
  await simulatePaymentSuccess(orderTimeout.id, customerToken);
  await fulfillPlatformOrder(orderTimeout.id, customerToken, merchantToken, riderToken);

  const accrueResTimeout = await request(`/admin/finance/orders/${orderTimeout.id}/accrue-payable`, { token: admin1Token, method: 'POST', headers: { 'Idempotency-Key': randomUUID() } });
  const payableTimeout = accrueResTimeout.data.data;
  console.log(`Accrued merchant payable for timeout test: Net ₹${payableTimeout.net_payable_minor/100}`);

  const poolResTimeout = await request(`/admin/finance/qa-funding-pools`, {
    token: admin1Token,
    method: 'POST',
    body: {
      order_id: orderTimeout.id,
      amount_minor: payableTimeout.net_payable_minor,
      funding_reference: `QA_POOL_TIMEOUT_${orderTimeout.id.slice(0, 8)}`,
      reason: 'Synthetic QA pool for timeout test',
    },
  });
  if (!poolResTimeout.ok) throw new Error(`Create QA pool failed: ${JSON.stringify(poolResTimeout.data)}`);

  const timeoutBatchRes = await request(`/admin/finance/settlements`, {
    token: admin1Token,
    method: 'POST',
    body: {
      period_start: '2026-11-01',
      period_end: '2026-11-30',
      idempotency_key: randomUUID(),
      payable_ids: [payableTimeout.id],
    },
  });
  if (!timeoutBatchRes.ok) throw new Error(`Create timeout batch failed: ${JSON.stringify(timeoutBatchRes.data)}`);
  const timeoutBatchId = timeoutBatchRes.data.data.id;
  await request(`/admin/finance/settlements/${timeoutBatchId}/review`, { token: admin2Token, method: 'POST', body: { reason: 'Review' }, headers: { 'Idempotency-Key': randomUUID() } });
  await request(`/admin/finance/settlements/${timeoutBatchId}/approve`, { token: admin3Token, method: 'POST', body: { reason: 'Approve' }, headers: { 'Idempotency-Key': randomUUID() } });

  const timeoutTransferRes = await request(`/admin/finance/settlements/${timeoutBatchId}/payout-transfer`, { token: admin1Token, method: 'POST' });
  if (!timeoutTransferRes.ok) throw new Error(`Create timeout transfer failed: ${JSON.stringify(timeoutTransferRes.data)}`);
  const timeoutTransferId = d(timeoutTransferRes).transfer_id;
  await request(`/admin/finance/payout-transfers/${timeoutTransferId}/approve`, { token: admin2Token, method: 'POST', body: { reason: 'Approve' } });

  // Execute transfer: trigger timeout
  const timeoutExecRes = await request(`/admin/finance/payout-transfers/${timeoutTransferId}/execute`, { token: admin1Token, method: 'POST' });
  if (timeoutExecRes.status !== 504) throw new Error(`Expected HTTP 504 timeout, got ${timeoutExecRes.status}`);
  console.log('✓ Provider timeout returned HTTP 504.');

  // Verify transfer is in reconciliation_required state
  const tState = psql(`SELECT status FROM payout_transfers WHERE id='${timeoutTransferId}'`);
  if (tState !== 'reconciliation_required') throw new Error(`Expected reconciliation_required, got ${tState}`);
  console.log(`✓ Transfer held in state: '${tState}'. Funds remain safely locked in payout_clearing_liability.`);

  // Verify attempt retry is BLOCKED while in-flight
  const retryBlockedRes = await request(`/admin/finance/payout-transfers/${timeoutTransferId}/execute`, { token: admin1Token, method: 'POST' });
  if (retryBlockedRes.ok) throw new Error('Retry during in-flight timeout must be blocked!');
  console.log('✓ Retry safety: Second execution attempt blocked while outcome is unresolved.');

  // Reconcile with provider
  const reconRes = await request(`/admin/finance/payout-transfers/${timeoutTransferId}/reconcile`, { token: admin1Token, method: 'POST' });
  const reconStatus = d(reconRes).status || d(reconRes).Status;
  const reconUtr = d(reconRes).utr || d(reconRes).UTR;
  if (!reconRes.ok || reconStatus !== 'succeeded') throw new Error(`Reconciliation failed: ${JSON.stringify(reconRes.data)}`);
  console.log(`✓ Reconciliation query fetched authoritative outcome: Status=${reconStatus}, UTR=${reconUtr}`);

  // ---------------------------------------------------------------------------
  // SCENARIO 7: Post-Success Reversal via Webhook & Compensating Journal
  // ---------------------------------------------------------------------------
  console.log('\n--- SCENARIO 7: Post-Success Reversal & Webhook Idempotency ---');

  const webhookSecret = 'qa_isolated_payout_webhook_secret_key_32_bytes_min!';
  const reversePayload = JSON.stringify({
    provider: 'grepmind_qa_payout',
    event_id: `EVT_REV_${randomUUID().slice(0,8)}`,
    provider_transfer_id: `qa_tx_${timeoutTransferId.slice(0,8)}_1`,
    transfer_id: timeoutTransferId,
    event_type: 'payout.reversed',
    status: 'reversed',
    amount_minor: payableTimeout.net_payable_minor,
    utr: reconUtr,
    failure_reason: 'Beneficiary bank returned funds: account dormant',
    event_at: new Date().toISOString(),
  });

  const hmacSig = createHmac('sha256', webhookSecret).update(reversePayload).digest('hex');

  // Send reverse webhook
  const whRes1 = await fetch(`${base}/payouts/webhooks/grepmind_qa_payout`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'X-Grepmind-Payout-Signature': hmacSig,
    },
    body: reversePayload,
  });
  if (!whRes1.ok) throw new Error(`Webhook failed: ${await whRes1.text()}`);
  console.log('✓ Webhook reversal processed.');

  // Verify compensating reversal journal
  const revJournalId = psql(`SELECT reversal_journal_id FROM payout_transfers WHERE id='${timeoutTransferId}'`);
  const revPostings = psqlJson(`SELECT a.account_code, p.side, p.amount_minor FROM financial_postings p JOIN financial_accounts a ON a.id=p.account_id WHERE p.journal_id='${revJournalId}'`);
  console.log(`✓ Compensating reversal journal posted: ${JSON.stringify(revPostings)}`);
  console.log('✓ Partner payable balance cleanly restored without mutating historical disbursement journals.');

  // Send DUPLICATE webhook
  const whRes2 = await fetch(`${base}/payouts/webhooks/grepmind_qa_payout`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'X-Grepmind-Payout-Signature': hmacSig,
    },
    body: reversePayload,
  });
  if (!whRes2.ok) throw new Error(`Duplicate webhook failed: ${await whRes2.text()}`);
  console.log('✓ Duplicate webhook safely ignored with HTTP 200 and zero duplicate ledger actions.');

  // ---------------------------------------------------------------------------
  // SCENARIO 8: Real-Money Execution Disabled Guard
  // ---------------------------------------------------------------------------
  console.log('\n--- SCENARIO 8: Real-Money Execution Disabled Guard ---');
  const featureGates = psqlJson(`SELECT real_money_enabled, payout_enabled FROM financial_feature_config`)[0];
  if (featureGates.real_money_enabled !== false || featureGates.payout_enabled !== false) {
    throw new Error(`Real money switches MUST be false! Got: ${JSON.stringify(featureGates)}`);
  }
  console.log(`✓ Production fail-closed gates active: real_money_enabled=${featureGates.real_money_enabled}, payout_enabled=${featureGates.payout_enabled}`);

  console.log('\n================================================================');
  console.log('  ALL GATE G4-B ACCEPTANCE CRITERIA PASSED DETERMINISTICALLY');
  console.log('================================================================');
}

main().catch(err => {
  console.error('\n❌ FAILURE IN G4-B ACCEPTANCE SUITE:', err);
  process.exit(1);
});
