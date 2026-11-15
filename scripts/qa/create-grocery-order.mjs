#!/usr/bin/env node

import { randomUUID } from 'node:crypto';
import { readQaOtp } from './qa-otp.mjs';

const base = process.env.QA_API_BASE || 'http://127.0.0.1:18083/api/v1';
const phone = process.env.QA_CUSTOMER_PHONE || '+919990000181';
const paymentMethod = process.argv[2] || 'cash_on_delivery';

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
  if (!response.ok) {
    throw new Error(`${method} ${path} returned HTTP ${response.status}: ${JSON.stringify(payload)}`);
  }
  return payload;
}

// 1. Authenticate Customer
const challenge = await request('/auth/otp/request', { method: 'POST', body: { phone_e164: phone } });
const challengeId = challenge?.data?.challenge_id;
const otp = await readQaOtp(challengeId, phone, challenge?.data?.expires_at);
const verified = await request('/auth/otp/verify', {
  method: 'POST',
  body: { phone_e164: phone, otp_code: otp, challenge_id: challengeId },
});
const token = verified?.data?.access_token;
if (!token) throw new Error('Customer authentication failed.');

// 2. Fetch Customer Addresses
const addresses = await request('/customer/addresses', { token });
const address = addresses?.data?.[0];
if (!address) throw new Error('Customer has no registered address.');

// 3. Request Quote for Kalinga Basmati Rice
const variantId = '4e300000-0000-4000-8000-000000000202';
const quote = await request('/platform/orders/quote', {
  token,
  method: 'POST',
  body: {
    vertical: 'grocery',
    address_id: address.id,
    items: [{ variant_id: variantId, quantity: 1 }],
  },
});

if (!quote?.data?.quote_id) {
  throw new Error(`Quote failed: ${JSON.stringify(quote)}`);
}

// 4. Submit Order
const idempotencyKey = randomUUID();
const order = await request('/platform/orders', {
  token,
  method: 'POST',
  headers: { 'Idempotency-Key': idempotencyKey },
  body: {
    quote_id: quote.data.quote_id,
    notes: `Test grocery order (${paymentMethod})`,
    payment_method: paymentMethod,
  },
});

console.log(JSON.stringify({
  success: true,
  order_id: order?.data?.id,
  reference_code: order?.data?.reference_code,
  payment_method: order?.data?.payment_method,
  payment_status: order?.data?.payment_status,
  total_minor: quote?.data?.total_minor_units,
  partner_business_id: quote?.data?.partner?.business_id,
  partner_name: quote?.data?.partner?.name,
}, null, 2));
