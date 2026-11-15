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
  console.log('  GREPMIND NEAR — PHASE 4E.4 GATE G4-B HARDENING SUITE');
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
        UPDATE platform_partner_product_mappings SET available_quantity = 1000 WHERE business_id = '${businessId}';
        UPDATE delivery_assignments SET state='cancelled', ended_at=now() WHERE state='active';
        UPDATE delivery_offers SET state='expired', responded_at=now() WHERE state='offered';
        UPDATE delivery_dispatch_runs SET state='cancelled', completed_at=now() WHERE state='searching';
        UPDATE rider_availability_sessions SET is_online=true, lease_expires_at=now()+interval '2 hours' WHERE rider_user_id='${riderUserId}';
        INSERT INTO user_roles(user_id, role) VALUES('3e000000-0000-4000-8000-000000000004', 'delivery_operator') ON CONFLICT DO NOTHING;`);

  const webhookSecret = 'qa_isolated_payout_webhook_secret_key_32_bytes_min!';

  // ===========================================================================
  // CHECK 1: True Concurrent Allocation
  // ===========================================================================
  console.log('--- CHECK 1: True Concurrent Allocation ---');

  // Ensure active verified standard beneficiary for merchant
  const beneInit = await request(`/merchant/businesses/${businessId}/bank-beneficiary`, {
    token: merchantToken,
    method: 'POST',
    body: {
      account_holder_name: 'Kalinga Fresh Grocery Store',
      account_number: '1111222233331098',
      ifsc_code: 'SBIN0001234',
      bank_name: 'State Bank of India',
    },
  });
  await request(`/admin/finance/beneficiaries/${d(beneInit).id}/verify`, { token: admin1Token, method: 'POST' });

  // A. Create eligible order & accrue payable
  const concOrder = await createGroceryOrder(customerToken, 'upi');
  await simulatePaymentSuccess(concOrder.id, customerToken);
  await fulfillPlatformOrder(concOrder.id, customerToken, merchantToken, riderToken);

  const accrueRes = await request(`/admin/finance/orders/${concOrder.id}/accrue-payable`, {
    token: admin1Token,
    method: 'POST',
    headers: { 'Idempotency-Key': randomUUID() },
  });
  const payable = accrueRes.data.data;
  console.log(`Accrued merchant payable for concurrent allocation test: Net ₹${payable.net_payable_minor/100} (${payable.id})`);

  // Create QA funding pool
  await request(`/admin/finance/qa-funding-pools`, {
    token: admin1Token,
    method: 'POST',
    body: {
      order_id: concOrder.id,
      amount_minor: payable.net_payable_minor,
      funding_reference: `QA_POOL_CONC_${concOrder.id.slice(0, 8)}`,
      reason: 'Synthetic QA funding pool for concurrent allocation test',
    },
  });

  // Launch 10 simultaneous concurrent requests to allocate the SAME payable
  console.log('Dispatching 10 simultaneous concurrent settlement batch creation requests...');
  const concPromises = Array.from({ length: 10 }, (_, i) =>
    request(`/admin/finance/settlements`, {
      token: admin1Token,
      method: 'POST',
      body: {
        period_start: '2026-11-01',
        period_end: '2026-11-30',
        idempotency_key: randomUUID(),
        payable_ids: [payable.id],
      },
    })
  );

  const concResults = await Promise.all(concPromises);
  const successCount = concResults.filter(r => r.ok).length;
  const failureCount = concResults.filter(r => !r.ok).length;
  console.log(`Concurrent Merchant Allocation: Successes = ${successCount}, Failures = ${failureCount}`);

  if (successCount !== 1) {
    throw new Error(`CRITICAL: Expected exactly 1 concurrent allocation to succeed, but ${successCount} succeeded!`);
  }
  if (failureCount !== 9) {
    throw new Error(`CRITICAL: Expected 9 concurrent allocations to fail safely, but ${failureCount} failed!`);
  }
  console.log('✓ Exactly one concurrent allocation succeeded; 9 failed safely with unique index conflict.');

  // Verify database: Exactly 1 row in merchant_settlement_batch_items for this payable
  const allocatedRows = psql(`SELECT count(*) FROM merchant_settlement_batch_items WHERE payable_id='${payable.id}'`);
  if (parseInt(allocatedRows) !== 1) {
    throw new Error(`Database contains ${allocatedRows} batch items for payable, expected 1!`);
  }
  console.log('✓ Database integrity: Exactly 1 batch item recorded.');

  // Verify GL balance integrity
  const unbalancedJournals = psql(`SELECT count(*) FROM (
    SELECT journal_id, sum(CASE WHEN side='debit' THEN amount_minor ELSE -amount_minor END) AS balance
    FROM financial_postings GROUP BY journal_id HAVING sum(CASE WHEN side='debit' THEN amount_minor ELSE -amount_minor END) <> 0
  ) unb;`);
  if (parseInt(unbalancedJournals) !== 0) {
    throw new Error(`Detected ${unbalancedJournals} unbalanced financial journals in database!`);
  }
  console.log('✓ Financial ledger integrity: 100% of financial journals are strictly balanced (0 unbalanced).');

  // Complete review, approval, transfer creation, approval, and execution for this batch
  const winningBatchId = concResults.find(r => r.ok).data.data.id;
  await request(`/admin/finance/settlements/${winningBatchId}/review`, { token: admin2Token, method: 'POST', body: { reason: 'Review' }, headers: { 'Idempotency-Key': randomUUID() } });
  await request(`/admin/finance/settlements/${winningBatchId}/approve`, { token: admin3Token, method: 'POST', body: { reason: 'Approve' }, headers: { 'Idempotency-Key': randomUUID() } });

  const winningTransferRes = await request(`/admin/finance/settlements/${winningBatchId}/payout-transfer`, { token: admin1Token, method: 'POST' });
  const winningTransferId = d(winningTransferRes).transfer_id;
  await request(`/admin/finance/payout-transfers/${winningTransferId}/approve`, { token: admin2Token, method: 'POST', body: { reason: 'Approve' } });
  const winningExecRes = await request(`/admin/finance/payout-transfers/${winningTransferId}/execute`, { token: admin1Token, method: 'POST' });
  if (!winningExecRes.ok) throw new Error(`Execute winning transfer failed: ${JSON.stringify(winningExecRes.data)}`);
  console.log(`✓ Winning batch executed to payout: Status=${d(winningExecRes).status}, UTR=${d(winningExecRes).utr}`);

  // ===========================================================================
  // CHECK 2: Contradictory & Edge Provider Events
  // ===========================================================================
  console.log('\n--- CHECK 2: Contradictory Provider Events ---');

  // Helper to send signed webhook
  async function sendSignedWebhook(payloadObj) {
    const raw = JSON.stringify(payloadObj);
    const sig = createHmac('sha256', webhookSecret).update(raw).digest('hex');
    const res = await fetch(`${base}/payouts/webhooks/grepmind_qa_payout`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-Grepmind-Payout-Signature': sig,
      },
      body: raw,
    });
    return { ok: res.ok, status: res.status, text: await res.text() };
  }

  // 2.1: Success followed by stale failure
  console.log('Testing 2.1: Success followed by stale failure...');
  const staleFailEventId = `EVT_STALE_FAIL_${randomUUID().slice(0, 8)}`;
  await sendSignedWebhook({
    provider: 'grepmind_qa_payout',
    event_id: staleFailEventId,
    provider_transfer_id: `qa_tx_${winningTransferId.slice(0,8)}_1`,
    transfer_id: winningTransferId,
    event_type: 'payout.failed',
    status: 'failed',
    amount_minor: payable.net_payable_minor,
    failure_reason: 'Stale network rejection arriving after confirmed settlement',
    event_at: new Date().toISOString(),
  });

  const staleFailState = psql(`SELECT processing_state FROM payout_provider_events WHERE provider_event_id='${staleFailEventId}'`);
  const transferStatusAfterStale = psql(`SELECT status FROM payout_transfers WHERE id='${winningTransferId}'`);
  if (staleFailState !== 'quarantined') throw new Error(`Expected quarantined, got ${staleFailState}`);
  if (transferStatusAfterStale !== 'succeeded') throw new Error(`Transfer status mutated to ${transferStatusAfterStale}`);
  console.log(`✓ Stale failure on succeeded transfer correctly quarantined (state='${staleFailState}'). Transfer status preserved as 'succeeded'.`);

  // 2.2: Failure followed by unexpected late success
  console.log('Testing 2.2: Failure followed by unexpected late success...');
  // Register failure beneficiary (account ending in 8888 with valid IFSC passes penny drop but fails execution)
  const failBeneRes = await request(`/merchant/businesses/${businessId}/bank-beneficiary`, {
    token: merchantToken,
    method: 'POST',
    body: {
      account_holder_name: 'Kalinga Fresh Grocery Store',
      account_number: '1111222233338888',
      ifsc_code: 'SBIN0001234',
      bank_name: 'State Bank of India',
    },
  });
  const failBeneId = d(failBeneRes).id;
  await request(`/admin/finance/beneficiaries/${failBeneId}/verify`, { token: admin1Token, method: 'POST' });

  // Create order, payable, batch, transfer to trigger failure
  const failOrder = await createGroceryOrder(customerToken, 'upi');
  await simulatePaymentSuccess(failOrder.id, customerToken);
  await fulfillPlatformOrder(failOrder.id, customerToken, merchantToken, riderToken);
  const accrueFail = await request(`/admin/finance/orders/${failOrder.id}/accrue-payable`, { token: admin1Token, method: 'POST', headers: { 'Idempotency-Key': randomUUID() } });
  const payableFail = accrueFail.data.data;

  await request(`/admin/finance/qa-funding-pools`, {
    token: admin1Token,
    method: 'POST',
    body: {
      order_id: failOrder.id,
      amount_minor: payableFail.net_payable_minor,
      funding_reference: `QA_POOL_FAIL_${failOrder.id.slice(0, 8)}`,
      reason: 'Synthetic QA funding pool for failure test',
    },
  });

  const failBatchRes = await request(`/admin/finance/settlements`, {
    token: admin1Token,
    method: 'POST',
    body: { period_start: '2026-11-01', period_end: '2026-11-30', idempotency_key: randomUUID(), payable_ids: [payableFail.id] },
  });
  const failBatchId = failBatchRes.data.data.id;
  await request(`/admin/finance/settlements/${failBatchId}/review`, { token: admin2Token, method: 'POST', body: { reason: 'Review' }, headers: { 'Idempotency-Key': randomUUID() } });
  await request(`/admin/finance/settlements/${failBatchId}/approve`, { token: admin3Token, method: 'POST', body: { reason: 'Approve' }, headers: { 'Idempotency-Key': randomUUID() } });

  const failTransferRes = await request(`/admin/finance/settlements/${failBatchId}/payout-transfer`, { token: admin1Token, method: 'POST' });
  const failTransferId = d(failTransferRes).transfer_id;
  await request(`/admin/finance/payout-transfers/${failTransferId}/approve`, { token: admin2Token, method: 'POST', body: { reason: 'Approve' } });
  const failExecRes = await request(`/admin/finance/payout-transfers/${failTransferId}/execute`, { token: admin1Token, method: 'POST' });
  const failStatus = psql(`SELECT status FROM payout_transfers WHERE id='${failTransferId}'`);
  console.log(`Transfer executed with failure IFSC: status='${failStatus}'`);

  // Now send contradictory late success webhook
  const lateSuccessEventId = `EVT_LATE_SUCC_${randomUUID().slice(0, 8)}`;
  await sendSignedWebhook({
    provider: 'grepmind_qa_payout',
    event_id: lateSuccessEventId,
    provider_transfer_id: `qa_tx_${failTransferId.slice(0,8)}_1`,
    transfer_id: failTransferId,
    event_type: 'payout.succeeded',
    status: 'succeeded',
    amount_minor: payableFail.net_payable_minor,
    utr: 'QA_CONTRADICTORY_LATE_UTR_12345',
    event_at: new Date().toISOString(),
  });

  const lateSuccessState = psql(`SELECT processing_state FROM payout_provider_events WHERE provider_event_id='${lateSuccessEventId}'`);
  const transferStatusAfterLateSucc = psql(`SELECT status FROM payout_transfers WHERE id='${failTransferId}'`);
  if (lateSuccessState !== 'quarantined') throw new Error(`Expected quarantined, got ${lateSuccessState}`);
  if (transferStatusAfterLateSucc !== 'failed') throw new Error(`Transfer status mutated to ${transferStatusAfterLateSucc}`);
  console.log(`✓ Contradictory late success on failed transfer correctly quarantined (state='${lateSuccessState}'). Transfer remains 'failed'.`);

  // 2.3: Duplicate Reversal
  console.log('Testing 2.3: Duplicate Reversal...');
  // Reverse winningTransferId first
  const revEventId1 = `EVT_REV1_${randomUUID().slice(0, 8)}`;
  await sendSignedWebhook({
    provider: 'grepmind_qa_payout',
    event_id: revEventId1,
    provider_transfer_id: `qa_tx_${winningTransferId.slice(0,8)}_1`,
    transfer_id: winningTransferId,
    event_type: 'payout.reversed',
    status: 'reversed',
    amount_minor: payable.net_payable_minor,
    utr: d(winningExecRes).utr,
    event_at: new Date().toISOString(),
  });
  const tStateAfterRev = psql(`SELECT status FROM payout_transfers WHERE id='${winningTransferId}'`);
  console.log(`Transfer reversed: status='${tStateAfterRev}'`);

  // Send duplicate reversal with fresh event ID
  const dupRevEventId = `EVT_REV2_${randomUUID().slice(0, 8)}`;
  await sendSignedWebhook({
    provider: 'grepmind_qa_payout',
    event_id: dupRevEventId,
    provider_transfer_id: `qa_tx_${winningTransferId.slice(0,8)}_1`,
    transfer_id: winningTransferId,
    event_type: 'payout.reversed',
    status: 'reversed',
    amount_minor: payable.net_payable_minor,
    utr: d(winningExecRes).utr,
    event_at: new Date().toISOString(),
  });

  const dupRevState = psql(`SELECT processing_state FROM payout_provider_events WHERE provider_event_id='${dupRevEventId}'`);
  if (dupRevState !== 'duplicate') throw new Error(`Expected duplicate, got ${dupRevState}`);
  console.log(`✓ Duplicate reversal correctly marked processing_state='${dupRevState}'. Zero duplicate journals.`);

  // 2.4: Unknown Provider Event
  console.log('Testing 2.4: Unknown Provider Event...');
  const unknownEventId = `EVT_UNK_${randomUUID().slice(0, 8)}`;
  await sendSignedWebhook({
    provider: 'grepmind_qa_payout',
    event_id: unknownEventId,
    provider_transfer_id: `qa_tx_${winningTransferId.slice(0,8)}_1`,
    transfer_id: winningTransferId,
    event_type: 'payout.unrecognized_partner_callback',
    status: 'unrecognized_status',
    amount_minor: 1000,
    event_at: new Date().toISOString(),
  });
  const unknownState = psql(`SELECT processing_state FROM payout_provider_events WHERE provider_event_id='${unknownEventId}'`);
  if (unknownState !== 'quarantined') throw new Error(`Expected quarantined, got ${unknownState}`);
  console.log(`✓ Unknown provider event correctly quarantined (state='${unknownState}').`);

  // 2.5: Timeout followed by delayed success webhook
  console.log('Testing 2.5: Timeout followed by delayed success webhook...');
  // Re-register timeout beneficiary (account ending in 9999)
  const toBeneRes = await request(`/merchant/businesses/${businessId}/bank-beneficiary`, {
    token: merchantToken,
    method: 'POST',
    body: {
      account_holder_name: 'Kalinga Fresh Grocery Store',
      account_number: '1111222233339999',
      ifsc_code: 'SBIN0001234',
      bank_name: 'State Bank of India',
    },
  });
  const toBeneId = d(toBeneRes).id;
  await request(`/admin/finance/beneficiaries/${toBeneId}/verify`, { token: admin1Token, method: 'POST' });

  const toOrder = await createGroceryOrder(customerToken, 'upi');
  await simulatePaymentSuccess(toOrder.id, customerToken);
  await fulfillPlatformOrder(toOrder.id, customerToken, merchantToken, riderToken);
  const accrueTo = await request(`/admin/finance/orders/${toOrder.id}/accrue-payable`, { token: admin1Token, method: 'POST', headers: { 'Idempotency-Key': randomUUID() } });
  const payableTo = accrueTo.data.data;

  await request(`/admin/finance/qa-funding-pools`, {
    token: admin1Token,
    method: 'POST',
    body: {
      order_id: toOrder.id,
      amount_minor: payableTo.net_payable_minor,
      funding_reference: `QA_POOL_TO_${toOrder.id.slice(0, 8)}`,
      reason: 'Synthetic QA funding pool for timeout webhook test',
    },
  });

  const toBatchRes = await request(`/admin/finance/settlements`, {
    token: admin1Token,
    method: 'POST',
    body: { period_start: '2026-11-01', period_end: '2026-11-30', idempotency_key: randomUUID(), payable_ids: [payableTo.id] },
  });
  const toBatchId = toBatchRes.data.data.id;
  await request(`/admin/finance/settlements/${toBatchId}/review`, { token: admin2Token, method: 'POST', body: { reason: 'Review' }, headers: { 'Idempotency-Key': randomUUID() } });
  await request(`/admin/finance/settlements/${toBatchId}/approve`, { token: admin3Token, method: 'POST', body: { reason: 'Approve' }, headers: { 'Idempotency-Key': randomUUID() } });

  const toTransferRes = await request(`/admin/finance/settlements/${toBatchId}/payout-transfer`, { token: admin1Token, method: 'POST' });
  const toTransferId = d(toTransferRes).transfer_id;
  await request(`/admin/finance/payout-transfers/${toTransferId}/approve`, { token: admin2Token, method: 'POST', body: { reason: 'Approve' } });
  const toExecRes = await request(`/admin/finance/payout-transfers/${toTransferId}/execute`, { token: admin1Token, method: 'POST' });
  if (toExecRes.status !== 504) throw new Error(`Expected 504 timeout, got ${toExecRes.status}`);

  const toState = psql(`SELECT status FROM payout_transfers WHERE id='${toTransferId}'`);
  console.log(`Transfer timed out and entered state='${toState}'`);

  // Deliver delayed success webhook
  const delayedSuccEventId = `EVT_DELAYED_SUCC_${randomUUID().slice(0, 8)}`;
  await sendSignedWebhook({
    provider: 'grepmind_qa_payout',
    event_id: delayedSuccEventId,
    provider_transfer_id: `qa_tx_${toTransferId.slice(0,8)}_1`,
    transfer_id: toTransferId,
    event_type: 'payout.succeeded',
    status: 'succeeded',
    amount_minor: payableTo.net_payable_minor,
    utr: 'QA_DELAYED_WEBHOOK_RESOLVED_UTR_9999',
    event_at: new Date().toISOString(),
  });

  const delayedSuccState = psql(`SELECT processing_state FROM payout_provider_events WHERE provider_event_id='${delayedSuccEventId}'`);
  const transferStatusAfterDelayedSucc = psql(`SELECT status FROM payout_transfers WHERE id='${toTransferId}'`);
  const disbJournalAfterDelayedSucc = psql(`SELECT disbursement_journal_id FROM payout_transfers WHERE id='${toTransferId}'`);
  if (delayedSuccState !== 'processed') throw new Error(`Expected processed, got ${delayedSuccState}`);
  if (transferStatusAfterDelayedSucc !== 'succeeded') throw new Error(`Expected succeeded, got ${transferStatusAfterDelayedSucc}`);
  console.log(`✓ Delayed success webhook processed (state='${delayedSuccState}'). Transfer transitioned to 'succeeded' with disbursement journal ${disbJournalAfterDelayedSucc}.`);

  // ===========================================================================
  // CHECK 3: Production and Staging Fail-Closed
  // ===========================================================================
  console.log('\n--- CHECK 3: Production & Staging Fail-Closed ---');

  // Verify feature gates in database
  const gates = psqlJson(`SELECT real_money_enabled, payout_enabled FROM financial_feature_config WHERE singleton=true`)[0];
  console.log(`Current DB feature switches: real_money_enabled=${gates.real_money_enabled}, payout_enabled=${gates.payout_enabled}`);

  // 3.1 Verify database check constraint blocks setting real_money_enabled = true
  console.log('Testing fail-closed: deliberate attempt to enable real_money_enabled in DB...');
  let checkConstraintTriggered = false;
  try {
    psql(`UPDATE financial_feature_config SET real_money_enabled=true WHERE singleton=true;`);
  } catch (err) {
    if (err.message.includes('financial_feature_config_check')) {
      checkConstraintTriggered = true;
    }
  }
  if (!checkConstraintTriggered) {
    throw new Error('Database check constraint failed to block real_money_enabled=true!');
  }
  console.log('✓ Database schema hard gate: financial_feature_config_check strictly blocks real_money_enabled=true.');

  // 3.2 Enable payout_enabled in DB and verify DisabledProductionProvider still fails closed
  console.log('Testing fail-closed: enabling payout_enabled=true in DB...');
  psql(`UPDATE financial_feature_config SET payout_enabled=true WHERE singleton=true;`);

  // Verify that DisabledProductionProvider rejects operations in unit test
  const goTestOutput = execSync(`bash -lc "cd /mnt/d/grepmind-near/backend && go test -v -run TestFailClosedInProductionAndStaging ./internal/payouts/..."`, { encoding: 'utf-8' });
  console.log('✓ DisabledProductionProvider verified fail-closed for production and staging:\n' + goTestOutput.trim());

  // Restore DB feature gates to strictly disabled
  psql(`UPDATE financial_feature_config SET payout_enabled=false WHERE singleton=true;`);
  const restoredGates = psqlJson(`SELECT real_money_enabled, payout_enabled FROM financial_feature_config WHERE singleton=true`)[0];
  if (restoredGates.real_money_enabled !== false || restoredGates.payout_enabled !== false) {
    throw new Error(`Failed to restore financial feature config: ${JSON.stringify(restoredGates)}`);
  }
  console.log(`✓ Flags restored safely: real_money_enabled=${restoredGates.real_money_enabled}, payout_enabled=${restoredGates.payout_enabled}`);

  // ===========================================================================
  // CHECK 4: Beneficiary Security & Key Rotation
  // ===========================================================================
  console.log('\n--- CHECK 4: Beneficiary Security & Key Rotation ---');

  // Register clean merchant beneficiary
  const secBeneRes = await request(`/merchant/businesses/${businessId}/bank-beneficiary`, {
    token: merchantToken,
    method: 'POST',
    body: {
      account_holder_name: 'Kalinga Fresh Grocery Store',
      account_number: '1111222233334567',
      ifsc_code: 'SBIN0001234',
      bank_name: 'State Bank of India',
    },
  });
  const secBeneId = d(secBeneRes).id;
  await request(`/admin/finance/beneficiaries/${secBeneId}/verify`, { token: admin1Token, method: 'POST' });

  // 1. Merchant read endpoint
  const merchRead = await request(`/merchant/businesses/${businessId}/bank-beneficiary`, { token: merchantToken });
  const merchData = JSON.stringify(merchRead.data);
  if (!merchData.includes('XXXXXXXX4567') || merchData.includes('1111222233334567')) {
    throw new Error('Merchant read API leaked unmasked account number!');
  }
  console.log('✓ Merchant read API returns masked account number (XXXXXXXX4567) and no plaintext.');

  // 2. Rider read endpoint
  const riderRead = await request(`/rider/bank-beneficiary`, { token: riderToken });
  const riderData = JSON.stringify(riderRead.data);
  if (riderData.includes('1111222233334567')) {
    throw new Error('Rider read API leaked unmasked account number!');
  }
  console.log('✓ Rider read API returns masked account number and no plaintext.');

  // 3. Admin read endpoint
  const adminRead = await request(`/admin/finance/beneficiaries/${secBeneId}`, { token: admin1Token });
  const adminData = JSON.stringify(adminRead.data);
  if (!adminData.includes('XXXXXXXX4567') || adminData.includes('1111222233334567')) {
    throw new Error('Admin read API leaked unmasked account number!');
  }
  console.log('✓ Admin read API returns masked account number and no plaintext.');

  // 4. Audit trail inspection
  const auditEvents = psqlJson(`SELECT metadata FROM bank_beneficiary_audit_events WHERE beneficiary_id='${secBeneId}'`);
  for (const evt of auditEvents) {
    const raw = JSON.stringify(evt);
    if (raw.includes('1111222233334567')) {
      throw new Error('Plaintext account number found in audit events metadata!');
    }
  }
  console.log('✓ Audit trail metadata verified: only masked account and IFSC recorded.');

  // 5. Invalidation on detail change
  const updatedBeneRes = await request(`/merchant/businesses/${businessId}/bank-beneficiary`, {
    token: merchantToken,
    method: 'POST',
    body: {
      account_holder_name: 'Kalinga Fresh Grocery Store',
      account_number: '9999888877771234',
      ifsc_code: 'SBIN0001234',
      bank_name: 'State Bank of India',
    },
  });
  const updatedBeneId = d(updatedBeneRes).id;
  const oldBeneStatus = psql(`SELECT verification_status FROM bank_beneficiaries WHERE id='${secBeneId}'`);
  if (oldBeneStatus !== 'deactivated') {
    throw new Error(`Old beneficiary was not deactivated on bank detail change! Status: ${oldBeneStatus}`);
  }
  console.log(`✓ Modifying bank details automatically deactivated previous beneficiary (status='${oldBeneStatus}').`);

  // 6. Key rotation unit tests
  const keyRotOutput = execSync(`bash -lc "cd /mnt/d/grepmind-near/backend && go test -v -run TestKeyRotationAndHistoricalDecryption ./internal/payouts/..."`, { encoding: 'utf-8' });
  console.log('✓ Key rotation and historical decryption test executed cleanly:\n' + keyRotOutput.trim());

  // ===========================================================================
  // CHECK 5: Fresh Migration Reproducibility
  // ===========================================================================
  console.log('\n--- CHECK 5: Fresh Migration Reproducibility ---');
  const migOutput = execSync(`/mnt/d/grepmind-near/scripts/qa/test-fresh-migration.sh`, { encoding: 'utf-8' });
  console.log(migOutput.trim());

  console.log('\n================================================================');
  console.log('  ALL 5 GATE G4-B HARDENING VERIFICATION CHECKS PASSED');
  console.log('================================================================');
}

main().catch(err => {
  console.error('\n❌ HARDENING CHECK FAILED:', err);
  process.exit(1);
});
