#!/usr/bin/env node
// Reports only availability/offer counts for isolated QA rider fixtures.
import { readQaOtp } from './qa-otp.mjs';
const base = process.env.PHASE3GD_API_BASE || 'http://127.0.0.1:18084/api/v1';
if (base !== 'http://127.0.0.1:18084/api/v1') throw new Error('Restricted to isolated Phase 3G-D API port 18084.');
async function request(path, { token, method = 'GET', body } = {}) {
  const response = await fetch(`${base}${path}`, { method, headers: { ...(body ? { 'Content-Type': 'application/json' } : {}), ...(token ? { Authorization: `Bearer ${token}` } : {}) }, ...(body ? { body: JSON.stringify(body) } : {}) });
  const payload = await response.json().catch(() => null);
  if (!response.ok) throw new Error(`${method} ${path} returned HTTP ${response.status}`);
  return payload?.data;
}
for (const [label, phone] of [['rider_a', '+919990000183'], ['rider_b', '+919990000185']]) {
  const challenge = await request('/auth/otp/request', { method: 'POST', body: { phone_e164: phone } });
  const challengeId = challenge?.challenge_id;
  const otp = await readQaOtp(challengeId, phone, challenge?.expires_at);
  const verified = await request('/auth/otp/verify', { method: 'POST', body: { phone_e164: phone, otp_code: otp, challenge_id: challengeId } });
  const token = verified?.access_token;
  if (!token) throw new Error(`${label} auth failed`);
  const availability = await request('/rider/availability', { token });
  const offers = await request('/rider/offers', { token });
  console.log(JSON.stringify({ rider: label, online: availability?.online === true, offer_count: Array.isArray(offers) ? offers.length : 0, offer_refs: Array.isArray(offers) ? offers.map(x => x.reference_code).filter(Boolean) : [] }));
}
