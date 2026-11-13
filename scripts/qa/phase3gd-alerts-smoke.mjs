#!/usr/bin/env node

// Authenticated smoke check for Phase 3G-D operations alerts. Restricted to QA.
import { readQaOtp } from './qa-otp.mjs';
const base = process.env.PHASE3GD_API_BASE || 'http://127.0.0.1:18084/api/v1';
if (base !== 'http://127.0.0.1:18084/api/v1') throw new Error('Restricted to isolated Phase 3G-D API port 18084.');

async function request(path, { token, method = 'GET', body } = {}) {
  const response = await fetch(`${base}${path}`, {
    method,
    headers: { ...(body ? { 'Content-Type': 'application/json' } : {}), ...(token ? { Authorization: `Bearer ${token}` } : {}) },
    ...(body ? { body: JSON.stringify(body) } : {}),
  });
  return { response, payload: await response.json().catch(() => null) };
}

async function authenticate(phone) {
  const challenge = await request('/auth/otp/request', { method: 'POST', body: { phone_e164: phone } });
  const challengeId = challenge.payload?.data?.challenge_id;
  const otp = await readQaOtp(challengeId, phone, challenge.payload?.data?.expires_at);
  const verified = await request('/auth/otp/verify', { method: 'POST', body: { phone_e164: phone, otp_code: otp, challenge_id: challengeId } });
  if (!verified.response.ok || !verified.payload?.data?.access_token) throw new Error('QA authentication failed.');
  return verified.payload.data.access_token;
}

const adminToken = await authenticate('+919990000184');
const adminAlerts = await request('/admin/delivery-operations/alerts', { token: adminToken });
const customerToken = await authenticate('+919990000181');
const customerAlerts = await request('/admin/delivery-operations/alerts', { token: customerToken });
if (adminAlerts.response.status !== 200) throw new Error(`delivery_operator alerts returned HTTP ${adminAlerts.response.status}`);
if (customerAlerts.response.status !== 403) throw new Error(`customer alerts authorization returned HTTP ${customerAlerts.response.status}, expected 403`);
if (adminAlerts.payload?.meta?.automatic_resolution !== false) throw new Error('Alerts did not explicitly report automatic_resolution=false.');
const safe = (adminAlerts.payload?.data ?? []).every((item) => !('otp' in item) && !('phone' in item) && !('address' in item) && !('rider_location' in item));
if (!safe) throw new Error('Sensitive rider/customer field found in alert response.');
console.log(JSON.stringify({ result: 'alerts_api_security_pass', admin_status: 200, customer_status: 403, alert_count: adminAlerts.payload?.data?.length ?? 0, automatic_resolution: false, response_field_check: 'passed' }, null, 2));
