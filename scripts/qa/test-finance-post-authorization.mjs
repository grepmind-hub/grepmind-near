#!/usr/bin/env node

import { readQaOtp } from './qa-otp.mjs';

const base = process.env.QA_API_BASE || 'http://127.0.0.1:18083/api/v1';

async function getToken(phone) {
  const challengeRes = await fetch(`${base}/auth/otp/request`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ phone_e164: phone }),
  });
  const challenge = await challengeRes.json();
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
  return verified?.data?.access_token;
}

const codOrderId = '1e923dbb-ec68-47ec-bb5e-be9792fbfd3d'; // GN-1E923DBB
const upiOrderId = '053335a3-7805-49ea-af9d-1e9f79ae8ba4'; // GN-053335A3

console.log('=== Step 1: Authenticating QA identities ===');
const customerToken = await getToken('+919990000181');
console.log('Customer (+919990000181) token acquired');

const merchantToken = await getToken('+919990000182');
console.log('Merchant (+919990000182) token acquired');

const riderToken = await getToken('+919990000183');
console.log('Rider (+919990000183) token acquired');

const adminNoFinanceToken = await getToken('+919990000177');
console.log('Admin without finance.post (+919990000177) token acquired');

const admin1Token = await getToken('+919990000174'); // has finance.configure & finance.post
console.log('Admin 1 (+919990000174) token acquired');

const admin2Token = await getToken('+919990000175'); // has finance.configure & finance.post
console.log('Admin 2 (+919990000175) token acquired');

console.log('\n=== Step 2: Testing DENIED finance.post authorization on unaccrued order ===');
const deniedTests = [
  { role: 'Customer', token: customerToken },
  { role: 'Merchant', token: merchantToken },
  { role: 'Rider', token: riderToken },
  { role: 'Admin without finance.post', token: adminNoFinanceToken },
];

for (const t of deniedTests) {
  const res = await fetch(`${base}/admin/finance/orders/${codOrderId}/accrue-payable`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${t.token}`, 'Content-Type': 'application/json' },
  });
  const body = await res.json().catch(() => ({}));
  console.log(`[DENIED] ${t.role} calling accrue-payable: HTTP ${res.status}`);
  console.log('Response body:', JSON.stringify(body));
  if (res.status !== 403) {
    throw new Error(`Expected HTTP 403 for ${t.role}, got ${res.status}`);
  }
}

console.log('\n=== Step 3: Checking eligible orders before posting ===');
const eligibleRes = await fetch(`${base}/admin/finance/eligible-orders`, {
  headers: { Authorization: `Bearer ${admin1Token}` },
});
const eligibleOrdersPayload = await eligibleRes.json();
const eligibleOrders = eligibleOrdersPayload.data || eligibleOrdersPayload;
console.log(`Eligible orders count: ${eligibleOrders.length}`);
console.log('Eligible orders references:', eligibleOrders.map(o => o.reference_code));
const upiInEligible = eligibleOrders.some(o => o.reference_code === 'GN-053335A3');
if (!upiInEligible) {
  throw new Error(`Expected UPI order GN-053335A3 in eligible orders`);
}

console.log('\n=== Step 4: Creating and Approving Commission Policy with Two-Person Rule ===');
// Admin 1 creates draft policy
const policyKey = 'grocery-platform-' + Date.now();
const createPolicyRes = await fetch(`${base}/admin/finance/commission-policies`, {
  method: 'POST',
  headers: { Authorization: `Bearer ${admin1Token}`, 'Content-Type': 'application/json' },
  body: JSON.stringify({
    policy_key: policyKey,
    version: 1,
    vertical: 'grocery',
    commission_type: 'percentage_bps',
    percentage_bps: 500, // 5%
    effective_from: '2026-01-01T00:00:00Z',
  }),
});
const policyPayload = await createPolicyRes.json();
const policyData = policyPayload.data || policyPayload;
console.log('Draft policy created HTTP', createPolicyRes.status, policyData);
if (createPolicyRes.status !== 201) {
  throw new Error(`Failed to create policy: ${JSON.stringify(policyPayload)}`);
}
const policyId = policyData.id;

// Negative check: Admin 1 attempts self-approval
const selfApproveRes = await fetch(`${base}/admin/finance/commission-policies/${policyId}/decision`, {
  method: 'POST',
  headers: { Authorization: `Bearer ${admin1Token}`, 'Content-Type': 'application/json' },
  body: JSON.stringify({ decision: 'approve', reason: 'Self approval attempt' }),
});
console.log('Admin 1 self-approval attempt: HTTP', selfApproveRes.status);
if (selfApproveRes.status !== 403) {
  throw new Error(`Expected HTTP 403 for self-approval, got ${selfApproveRes.status}`);
}

// Admin 2 rejects the duplicate draft policy (distinct approver) to avoid overlapping policy ranges
const decideRes = await fetch(`${base}/admin/finance/commission-policies/${policyId}/decision`, {
  method: 'POST',
  headers: { Authorization: `Bearer ${admin2Token}`, 'Content-Type': 'application/json' },
  body: JSON.stringify({ decision: 'reject', reason: 'Rejected duplicate draft in favor of approved grocery-platform-standard' }),
});
const decidePayload = await decideRes.json();
const decideData = decidePayload.data || decidePayload;
console.log('Admin 2 independent rejection HTTP', decideRes.status, decideData);
if (decideRes.status !== 200 || decideData.status !== 'rejected') {
  throw new Error(`Failed to reject duplicate policy: ${JSON.stringify(decidePayload)}`);
}

console.log('\n=== Step 5: Testing PERMITTED finance.post on COD Order (GN-1E923DBB) ===');
const postCodRes = await fetch(`${base}/admin/finance/orders/${codOrderId}/accrue-payable`, {
  method: 'POST',
  headers: { Authorization: `Bearer ${admin1Token}`, 'Content-Type': 'application/json' },
});
const postCodPayload = await postCodRes.json();
const postCodBody = postCodPayload.data || postCodPayload;
console.log(`Permitted COD accrue-payable HTTP ${postCodRes.status}`);
console.log('Response:', JSON.stringify(postCodBody, null, 2));
if (postCodRes.status !== 200 && postCodRes.status !== 201) {
  throw new Error(`Expected HTTP 200 or 201 for permitted COD posting, got ${postCodRes.status}: ${JSON.stringify(postCodPayload)}`);
}

console.log('\n=== Step 6: Testing IDEMPOTENT replay of COD Order posting ===');
const replayCodRes = await fetch(`${base}/admin/finance/orders/${codOrderId}/accrue-payable`, {
  method: 'POST',
  headers: { Authorization: `Bearer ${admin1Token}`, 'Content-Type': 'application/json' },
});
const replayCodPayload = await replayCodRes.json();
const replayCodBody = replayCodPayload.data || replayCodPayload;
console.log(`Replay COD accrue-payable HTTP ${replayCodRes.status}`);
console.log('Response:', JSON.stringify(replayCodBody, null, 2));
if ((replayCodRes.status !== 200 && replayCodRes.status !== 201) || !replayCodBody.idempotent_replay) {
  throw new Error(`Expected HTTP 200/201 with idempotent_replay=true, got ${replayCodRes.status}`);
}

console.log('\n=== Step 7: Verifying selective posting: UPI Order remains unaccrued ===');
const eligibleMidRes = await fetch(`${base}/admin/finance/eligible-orders`, {
  headers: { Authorization: `Bearer ${admin1Token}` },
});
const eligibleMidPayload = await eligibleMidRes.json();
const eligibleMidOrders = eligibleMidPayload.data || eligibleMidPayload;
console.log(`Remaining eligible orders count: ${eligibleMidOrders.length}`);
console.log('Remaining eligible orders references:', eligibleMidOrders.map(o => o.reference_code));
const codStillEligible = eligibleMidOrders.some(o => o.reference_code === 'GN-1E923DBB');
const upiStillEligible = eligibleMidOrders.some(o => o.reference_code === 'GN-053335A3');
if (codStillEligible || !upiStillEligible) {
  throw new Error(`Expected COD order GN-1E923DBB removed and UPI order GN-053335A3 remaining, got codEligible=${codStillEligible}, upiEligible=${upiStillEligible}`);
}

console.log('\n=== Step 8: Testing PERMITTED finance.post on UPI Order (GN-053335A3) ===');
const postUpiRes = await fetch(`${base}/admin/finance/orders/${upiOrderId}/accrue-payable`, {
  method: 'POST',
  headers: { Authorization: `Bearer ${admin1Token}`, 'Content-Type': 'application/json' },
});
const postUpiPayload = await postUpiRes.json();
const postUpiBody = postUpiPayload.data || postUpiPayload;
console.log(`Permitted UPI accrue-payable HTTP ${postUpiRes.status}`);
console.log('Response:', JSON.stringify(postUpiBody, null, 2));
if (postUpiRes.status !== 200 && postUpiRes.status !== 201) {
  throw new Error(`Expected HTTP 200 or 201 for permitted UPI posting, got ${postUpiRes.status}: ${JSON.stringify(postUpiPayload)}`);
}

console.log('\n=== Step 9: Verifying both orders are now posted and removed from eligible ===');
const eligibleFinalRes = await fetch(`${base}/admin/finance/eligible-orders`, {
  headers: { Authorization: `Bearer ${admin1Token}` },
});
const eligibleFinalPayload = await eligibleFinalRes.json();
const eligibleFinalOrders = eligibleFinalPayload.data || eligibleFinalPayload;
console.log(`Final eligible orders count: ${eligibleFinalOrders.length}`);
console.log('Final eligible orders references:', eligibleFinalOrders.map(o => o.reference_code));
const codFinallyEligible = eligibleFinalOrders.some(o => o.reference_code === 'GN-1E923DBB');
const upiFinallyEligible = eligibleFinalOrders.some(o => o.reference_code === 'GN-053335A3');
if (codFinallyEligible || upiFinallyEligible) {
  throw new Error(`Expected neither GN-1E923DBB nor GN-053335A3 in eligible orders, got cod=${codFinallyEligible}, upi=${upiFinallyEligible}`);
}

console.log('\n=== ALL ADMIN FINANCE.POST AUTHORIZATION STEPS COMPLETED SUCCESSFULLY! ===');
