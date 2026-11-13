#!/usr/bin/env node

// Creates exactly one unpaid Phase 3G-D customer order on the isolated QA API.
// Never use this script against shared development or production services.
import { randomUUID } from 'node:crypto';
import { readQaOtp } from './qa-otp.mjs';

const allowedBases = new Set([
  'http://127.0.0.1:18083/api/v1',
  'http://127.0.0.1:18084/api/v1',
]);
const base = process.env.PHASE3GD_API_BASE || 'http://127.0.0.1:18084/api/v1';
if (!allowedBases.has(base)) {
  throw new Error('Restricted to the isolated Phase 3G-D QA APIs on localhost ports 18083 or 18084.');
}
const phone = '+919990000181';
const localityId = '02200000-0000-4000-8000-000000000101';

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
  if (!response.ok) throw new Error(`${method} ${path} returned HTTP ${response.status} (${payload?.error?.code || 'unknown'})`);
  return payload;
}

const challenge = await request('/auth/otp/request', { method: 'POST', body: { phone_e164: phone } });
const challengeId = challenge?.data?.challenge_id;
const otp = await readQaOtp(challengeId, phone, challenge?.data?.expires_at);
const verified = await request('/auth/otp/verify', { method: 'POST', body: { phone_e164: phone, otp_code: otp, challenge_id: challengeId } });
const token = verified?.data?.access_token;
if (!token) throw new Error('QA customer authentication failed.');

const addresses = await request('/customer/addresses', { token });
const address = addresses?.data?.find((item) => item.id === '3d000000-0000-4000-8000-000000000301' && item.locality_id === localityId);
if (!address) throw new Error('Expected isolated Kuanpal customer address was not returned.');

const catalog = await request(`/catalog/products?vertical=food&city=Cuttack&locality_id=${localityId}&limit=20`);
const product = catalog?.data?.find((item) => item.sku === 'P3GD-QA-FOOD-KUANPAL' && item.status === 'active');
const variant = product?.variants?.find((item) => item.sku === 'P3GD-QA-FOOD-KUANPAL-REG' && item.is_active);
if (!variant) throw new Error('Active Phase 3G-D QA product is unavailable.');

const quote = await request('/platform/orders/quote', {
  token, method: 'POST',
  body: { vertical: 'food', address_id: address.id, items: [{ variant_id: variant.id, quantity: 1 }] },
});
if (!quote?.data?.quote_id || !quote?.data?.partner?.business_id) throw new Error('Quote did not select the expected eligible partner.');

const idempotencyKey = randomUUID();
const submit = () => request('/platform/orders', {
  token, method: 'POST', headers: { 'Idempotency-Key': idempotencyKey },
  body: { quote_id: quote.data.quote_id, notes: 'Phase 3G-D isolated recovery QA order.' },
});
const order = await submit();
const replay = await submit();
if (!order?.data?.id || replay?.data?.id !== order.data.id) throw new Error('Idempotent replay did not return the same order.');
if (order.data.payment_status !== 'not_collected') throw new Error('Unexpected payment status; refusing QA acceptance.');

console.log(JSON.stringify({
  result: 'isolated_qa_order_created',
  order_id: order.data.id,
  reference_code: order.data.reference_code,
  locality: 'Kuanpal, Cuttack',
  product_sku: product.sku,
  partner_business_id: quote.data.partner.business_id,
  idempotency_replay: true,
  payment_status: order.data.payment_status,
}, null, 2));
