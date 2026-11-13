#!/usr/bin/env node

// Live API half of Phase 2E acceptance. This uses only the disposable QA API
// and seeded QA accounts; it never prints OTPs, access tokens, or refresh tokens.
import { randomUUID } from 'node:crypto';
import { readQaOtp } from './qa-otp.mjs';

const base = process.env.PHASE2E_API_BASE || 'http://127.0.0.1:8084/api/v1';
if (base !== 'http://127.0.0.1:8084/api/v1') {
  throw new Error('This acceptance script is restricted to the isolated Phase 2E QA API.');
}
const customerPhone = '+919990000007';
const localityId = '02200000-0000-4000-8000-000000000101'; // Cuttack → Kuanpal

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
    const error = new Error(`${method} ${path}: HTTP ${response.status} ${payload?.error?.code || ''}`.trim());
    error.status = response.status;
    throw error;
  }
  return { response, payload };
}

const otpResponse = await request('/auth/otp/request', {
  method: 'POST', body: { phone_e164: customerPhone },
});
const challengeId = otpResponse.payload?.data?.challenge_id;
const otp = await readQaOtp(challengeId, customerPhone, otpResponse.payload?.data?.expires_at);

const verified = await request('/auth/otp/verify', {
  method: 'POST', body: { phone_e164: customerPhone, otp_code: otp, challenge_id: challengeId },
});
const token = verified.payload?.data?.access_token;
if (!token) throw new Error('QA customer verification did not return an access token.');

const addressResponse = await request('/customer/addresses', { token });
let address = addressResponse.payload?.data?.find?.(item => item.locality_id === localityId);
if (!address) {
  const created = await request('/customer/addresses', {
    token,
    method: 'POST',
    body: {
      label: 'Home', recipient_name: 'Phase 2E QA Customer', address_line1: 'QA Test Lane',
      locality: 'Kuanpal', landmark: 'QA marker', city: 'Cuttack', state: 'Odisha',
      postal_code: '753001', contact_phone: customerPhone, locality_id: localityId, is_default: true,
    },
  });
  address = created.payload?.data;
}
if (!address?.id) throw new Error('No Cuttack/Kuanpal QA delivery address is available.');

const catalog = await request(`/catalog/products?vertical=food&city=Cuttack&locality_id=${localityId}&limit=20`);
const product = catalog.payload?.data?.find(item => item.sku === 'P2E-QA-FOOD-CTK' && item.status === 'active');
const variant = product?.variants?.find(item => item.is_active);
if (!variant) throw new Error('Active Kuanpal QA Food product variant was not found.');
if (product.image_urls?.length !== 1) throw new Error('Expected the QA product to have exactly one uploaded test image.');

// Customer upload boundary: platform-catalog media must be admin-only.
// This request intentionally sends only a tiny valid image to disposable MinIO.
const imageBytes = Buffer.from(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/lXcAAAAASUVORK5CYII=',
  'base64',
);
const form = new FormData();
form.append('purpose', 'platform-catalog');
form.append('file', new Blob([imageBytes], { type: 'image/png' }), 'qa-unauthorized.png');
const uploadResponse = await fetch(`${base}/media/upload`, {
  method: 'POST', headers: { Authorization: `Bearer ${token}` }, body: form,
});
let unauthorizedMediaId;
if (uploadResponse.ok) {
  const uploaded = await uploadResponse.json();
  unauthorizedMediaId = uploaded?.data?.id;
  console.log('SECURITY_FINDING: customer upload of platform-catalog media was accepted.');
} else if (uploadResponse.status === 403) {
  console.log('SECURITY_CHECK: customer upload of platform-catalog media denied (403).');
} else {
  throw new Error(`Unexpected customer platform-catalog upload status: ${uploadResponse.status}`);
}

const quote = await request('/platform/orders/quote', {
  token,
  method: 'POST',
  body: { vertical: 'food', address_id: address.id, items: [{ variant_id: variant.id, quantity: 1 }] },
});
const quoteData = quote.payload?.data;
if (!quoteData?.quote_id || !quoteData?.partner?.business_id) throw new Error('Server quote did not select an eligible fulfillment partner.');
if (quoteData.payment_status && quoteData.payment_status !== 'not_collected') throw new Error('Quote exposed an unexpected payment state.');

const idempotencyKey = randomUUID();
const submit = () => request('/platform/orders', {
  token, method: 'POST', headers: { 'Idempotency-Key': idempotencyKey },
  body: { quote_id: quoteData.quote_id, notes: 'Phase 2E disposable QA order.' },
});
const first = await submit();
const retry = await submit();
const order = first.payload?.data;
if (!order?.id || retry.payload?.data?.id !== order.id) throw new Error('Idempotent retry did not return the same QA order.');
if (order.payment_status !== 'not_collected') throw new Error('QA order is not in the required unpaid state.');

const orderDetail = await request(`/orders/${order.id}`, { token });
const orderHistory = await request('/customer/orders?order_type=platform_order&limit=20', { token });
if (orderDetail.payload?.data?.id !== order.id) throw new Error('Exact customer order detail did not return the submitted order.');
if (!orderHistory.payload?.data?.some?.(item => item.id === order.id)) throw new Error('Submitted QA order did not appear in customer order history.');

console.log(JSON.stringify({
  result: 'customer_api_checkout_pass',
  locality: 'Kuanpal, Cuttack',
  vertical: 'food',
  productSku: product.sku,
  hasImage: true,
  quoteSelectedPartner: quoteData.partner.name || quoteData.partner.id,
  orderId: order.id,
  referenceCode: order.reference_code,
  paymentStatus: order.payment_status,
  idempotentRetry: retry.response.status === 200 && retry.payload?.meta?.idempotent_replay === true,
  orderDetailAndHistory: 'verified',
  unauthorizedMediaUploadAccepted: Boolean(unauthorizedMediaId),
  unauthorizedMediaId: unauthorizedMediaId || undefined,
}, null, 2));
