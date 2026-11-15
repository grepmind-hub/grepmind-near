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
  const otp = await readQaOtp(challengeId, phone, challenge?.data?.expires_at);
  const verifyRes = await fetch(`${base}/auth/otp/verify`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ phone_e164: phone, otp_code: otp, challenge_id: challengeId }),
  });
  const verified = await verifyRes.json();
  return verified?.data?.access_token;
}

const customerToken = await getToken('+919990000181');
const merchantToken = await getToken('+919990000182');
const riderToken = await getToken('+919990000183');

const results = [];

// Test 1: Customer attempting to call admin financial endpoint
{
  const res = await fetch(`${base}/admin/audit-logs`, {
    headers: { Authorization: `Bearer ${customerToken}` },
  });
  results.push({
    test: 'Customer accessing Admin audit logs',
    status: res.status,
    expected: 403,
    passed: res.status === 403,
  });
}

// Test 2: Customer attempting to mark merchant order ready
{
  const res = await fetch(`${base}/merchant/orders/GN-053335A3/ready`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${customerToken}`, 'Content-Type': 'application/json' },
  });
  results.push({
    test: 'Customer calling merchant ready endpoint',
    status: res.status,
    expected: [403, 404],
    passed: res.status === 403 || res.status === 404,
  });
}

// Test 3: Rider attempting to call merchant endpoints
{
  const res = await fetch(`${base}/merchant/businesses/4e300000-0000-4000-8000-000000000101/catalog-capabilities`, {
    headers: { Authorization: `Bearer ${riderToken}` },
  });
  results.push({
    test: 'Rider accessing merchant business capabilities',
    status: res.status,
    expected: 403,
    passed: res.status === 403,
  });
}

// Test 4: Rider attempting to mark delivery completed without delivery code
{
  const res = await fetch(`${base}/rider/deliveries/d8bcffa1-ee8e-4206-a3bc-224b3dcf8f03/complete`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${riderToken}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({}),
  });
  results.push({
    test: 'Rider completing delivery without code',
    status: res.status,
    expected: [400, 403, 404, 422],
    passed: res.status >= 400 && res.status < 500,
  });
}

// Test 5: Unauthenticated access to financial journals
{
  const res = await fetch(`${base}/admin/finance/journals`);
  results.push({
    test: 'Unauthenticated access to financial journals',
    status: res.status,
    expected: [401, 403, 404],
    passed: res.status === 401 || res.status === 403 || res.status === 404,
  });
}

console.log(JSON.stringify(results, null, 2));
