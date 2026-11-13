#!/usr/bin/env node

// Read-only order verification for the disposable Phase 2E final acceptance run.
// Authenticates a QA customer against the isolated local API and never prints OTPs or tokens.
import { readQaOtp } from './qa-otp.mjs';
const base = process.env.PHASE2E_API_BASE || 'http://127.0.0.1:8084/api/v1';
if (base !== 'http://127.0.0.1:8084/api/v1') {
  throw new Error('This verifier is restricted to the isolated Phase 2E QA API.');
}
const orderId = process.argv[2];
if (!/^[0-9a-f-]{36}$/i.test(orderId || '')) throw new Error('Pass the exact QA order UUID.');
const customerPhone = '+919990000013';

async function request(path, { method = 'GET', token, body } = {}) {
  const response = await fetch(`${base}${path}`, {
    method,
    headers: {
      ...(body === undefined ? {} : { 'Content-Type': 'application/json' }),
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
    ...(body === undefined ? {} : { body: JSON.stringify(body) }),
  });
  const payload = await response.json().catch(() => null);
  if (!response.ok) throw new Error(`${method} ${path} returned HTTP ${response.status}.`);
  return payload?.data;
}

const issued = await request('/auth/otp/request', {
  method: 'POST', body: { phone_e164: customerPhone },
});
const challengeId = issued?.challenge_id;
const otp = await readQaOtp(challengeId, customerPhone, issued?.expires_at);
const verified = await request('/auth/otp/verify', {
  method: 'POST', body: { phone_e164: customerPhone, otp_code: otp, challenge_id: challengeId },
});
const token = verified?.access_token;
if (!token) throw new Error('QA customer authentication returned no access token.');

const [order, history] = await Promise.all([
  request(`/orders/${orderId}`, { token }),
  request('/customer/orders?order_type=platform_order&limit=20', { token }),
]);
if (order?.id !== orderId) throw new Error('Exact-order API returned a different order.');
if (!history?.some?.(item => item.id === orderId)) throw new Error('Order is absent from this customer’s order history.');
const timeline = (order.status_events || []).map(event => event.status);
const expected = ['placed', 'accepted', 'preparing', 'ready_for_pickup'];
if (JSON.stringify(timeline) !== JSON.stringify(expected)) {
  throw new Error(`Unexpected order timeline: ${timeline.join(' → ') || '(empty)'}`);
}
if (order.status !== 'ready_for_pickup' || order.payment_status !== 'not_collected') {
  throw new Error('Order is not ready for pickup with payment uncollected.');
}

console.log(JSON.stringify({
  result: 'PASS', orderId: order.id, referenceCode: order.reference_code,
  status: order.status, paymentStatus: order.payment_status,
  timeline, inCustomerOrderHistory: true,
  riderAssignmentPresent: Boolean(order.rider_id || order.delivery?.rider_id),
  etaPresent: Boolean(order.estimated_delivery_at || order.delivery?.eta),
}, null, 2));
