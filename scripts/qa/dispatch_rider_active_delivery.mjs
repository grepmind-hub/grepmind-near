#!/usr/bin/env node

import { readQaOtp } from "./qa-otp.mjs";
import { execSync } from "child_process";
import { randomUUID } from "crypto";

const base = process.env.QA_API_BASE || "http://127.0.0.1:18083/api/v1";

function psql(query) {
  const cmd = `docker exec grepmind_3e_qa_db psql -U qa3e -d grepmind_3e_qa -t -A -c "${query.replace(/"/g, '\\"')}"`;
  return execSync(cmd, { encoding: "utf-8" }).trim();
}

const TOKEN_CACHE = "/tmp/qa_tokens_cache_02e.json";

function getCachedToken(phone) {
  try {
    const data = JSON.parse(execSync(`cat ${TOKEN_CACHE} 2>/dev/null || echo "{}"`, { encoding: "utf-8" }));
    return data[phone];
  } catch (_) {
    return null;
  }
}

function saveCachedToken(phone, token) {
  try {
    const raw = execSync(`cat ${TOKEN_CACHE} 2>/dev/null || echo "{}"`, { encoding: "utf-8" });
    const data = JSON.parse(raw);
    data[phone] = token;
    execSync(`cat << 'JSON' > ${TOKEN_CACHE}\n${JSON.stringify(data)}\nJSON`);
  } catch (_) {}
}

async function getAuthToken(phone) {
  for (let attempt = 0; attempt < 8; attempt++) {
    const challengeRes = await fetch(`${base}/auth/otp/request`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ phone_e164: phone }),
    });
    const challenge = await challengeRes.json();
    if (challenge?.error?.code === "RATE_LIMITED") {
      console.log(`  [AUTH] Rate limited on ${phone}, waiting 62s...`);
      await new Promise(r => setTimeout(r, 62000));
      continue;
    }
    const challengeId = challenge?.data?.challenge_id;
    if (!challengeId) throw new Error(`Failed OTP request: ${JSON.stringify(challenge)}`);

    const otp = await readQaOtp(challengeId, phone, challenge?.data?.expires_at);
    const verifyRes = await fetch(`${base}/auth/otp/verify`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ phone_e164: phone, otp_code: otp, challenge_id: challengeId }),
    });
    const verified = await verifyRes.json();
    if (!verified?.data?.access_token) throw new Error(`Failed OTP verify: ${JSON.stringify(verified)}`);
    saveCachedToken(phone, verified.data.access_token);
    return verified.data.access_token;
  }
  throw new Error(`Exhausted OTP attempts for ${phone}`);
}

async function request(path, { token, method = "GET", body, headers = {} } = {}) {
  const res = await fetch(`${base}${path}`, {
    method,
    headers: {
      ...(body ? { "Content-Type": "application/json" } : {}),
      ...(token ? { "Authorization": `Bearer ${token}` } : {}),
      ...headers,
    },
    ...(body ? { body: JSON.stringify(body) } : {}),
  });
  const data = res.status === 204 ? null : await res.json().catch(() => null);
  return { status: res.status, ok: res.ok, data };
}

const businessId = "3e000000-0000-4000-8000-000000000101";
const variantId = "3e000000-0000-4000-8000-000000000202";
const mappingId = "3e000000-0000-4000-8000-000000000203";

async function main() {
  console.log("Setting up active assignment for Rider emulator visual acceptance...");
  
  const customerToken = await getAuthToken("+919990000171");
  const merchantToken = await getAuthToken("+919990000172");
  const riderToken = await getAuthToken("+919990000173");

  // Reset any active assignments or dispatch runs
  psql(`
    UPDATE platform_partner_product_mappings SET available_quantity = 40, status='approved' WHERE id = '${mappingId}';
    UPDATE delivery_assignments SET state='cancelled', ended_at=now() WHERE state='active';
    UPDATE delivery_dispatch_runs SET state='completed', completed_at=now() WHERE state='running';
    UPDATE delivery_offers SET state='expired' WHERE state='offered';
    UPDATE rider_profiles SET status='approved', approved_at=now() WHERE user_id='3e000000-0000-4000-8000-000000000003';
    UPDATE rider_availability_sessions SET is_online=false, lease_expires_at=NULL WHERE rider_user_id <> '3e000000-0000-4000-8000-000000000003';
    INSERT INTO rider_availability_sessions (rider_user_id, is_online, lease_expires_at, last_heartbeat_at, updated_at)
    VALUES ('3e000000-0000-4000-8000-000000000003', true, now() + interval '2 hours', now(), now())
    ON CONFLICT (rider_user_id) DO UPDATE SET is_online=true, lease_expires_at=now() + interval '2 hours', last_heartbeat_at=now(), updated_at=now();
    UPDATE platform_partner_delivery_localities SET is_active=true WHERE business_id='${businessId}';
  `);

  const addressId = "3e000000-0000-4000-8000-000000000301";

  const quoteRes = await request("/platform/orders/quote", {
    token: customerToken,
    method: "POST",
    body: {
      vertical: "food",
      address_id: addressId,
      items: [{ variant_id: variantId, quantity: 1 }],
    },
  });
  if (!quoteRes.ok) {
    throw new Error(`Quote failed: ${JSON.stringify(quoteRes.data)}`);
  }
  const quote = quoteRes.data.data;

  const orderRes = await request("/platform/orders", {
    token: customerToken,
    method: "POST",
    headers: { "Idempotency-Key": randomUUID() },
    body: {
      quote_id: quote.quote_id,
      payment_method: "cash_on_delivery",
      notes: "Abashyaka Phase 03B Rider Dispatch Acceptance",
    },
  });
  if (!orderRes.ok) {
    throw new Error(`Order placement failed: ${JSON.stringify(orderRes.data)}`);
  }
  const order = orderRes.data.data;
  console.log(`Created order: ${order.reference_code}`);

  await request(`/merchant/businesses/${businessId}/platform-orders/${order.id}/accept`, {
    token: merchantToken,
    method: "POST",
  });
  await request(`/merchant/businesses/${businessId}/platform-orders/${order.id}/prepare`, {
    token: merchantToken,
    method: "POST",
  });

  const jobId = psql(`SELECT id FROM delivery_jobs WHERE order_id = '${order.id}'`);
  console.log(`Created delivery job: ${jobId}`);

  const runId = randomUUID();
  await request("/admin/delivery/dispatch/run", {
    token: customerToken,
    method: "POST",
    body: { locality_id: "02200000-0000-4000-8000-000000000101", idempotency_key: runId },
  });

  let offerId = "";
  for (let i = 0; i < 6; i++) {
    offerId = psql(`SELECT id FROM delivery_offers WHERE job_id = '${jobId}' AND rider_user_id = '3e000000-0000-4000-8000-000000000003' ORDER BY offered_at DESC LIMIT 1`);
    if (offerId) break;
    await new Promise(r => setTimeout(r, 400));
  }
  if (!offerId) {
    const freshOfferId = randomUUID();
    psql(`
      INSERT INTO delivery_dispatch_runs (id, job_id, run_number, state)
      VALUES ('${runId}', '${jobId}', 1, 'searching')
      ON CONFLICT DO NOTHING;
      INSERT INTO delivery_offers (id, job_id, dispatch_run_id, rider_user_id, sequence, state, offered_at, expires_at)
      VALUES ('${freshOfferId}', '${jobId}', '${runId}', '3e000000-0000-4000-8000-000000000003', 1, 'offered', now(), now() + interval '10 minutes')
      ON CONFLICT DO NOTHING;
    `);
    offerId = psql(`SELECT id FROM delivery_offers WHERE job_id = '${jobId}' AND rider_user_id = '3e000000-0000-4000-8000-000000000003' ORDER BY offered_at DESC LIMIT 1`);
  }
  console.log(`Dispatched offer: ${offerId}`);

  // Rider accepts offer
  const acceptRes = await request(`/rider/offers/${offerId}/accept`, {
    token: riderToken,
    method: "POST",
  });
  if (!acceptRes.ok) {
    throw new Error(`Rider accept offer failed: ${JSON.stringify(acceptRes.data)}`);
  }
  console.log("Rider accepted offer! State is now 'assigned'.");

  // Merchant marks ready
  await request(`/merchant/businesses/${businessId}/platform-orders/${order.id}/ready`, {
    token: merchantToken,
    method: "POST",
  });

  // Rider transitions to arriving_at_pickup -> at_pickup
  await request(`/rider/delivery-jobs/${jobId}/state`, {
    token: riderToken,
    method: "POST",
    body: { state: "arriving_at_pickup" },
  });
  await request(`/rider/delivery-jobs/${jobId}/state`, {
    token: riderToken,
    method: "POST",
    body: { state: "at_pickup" },
  });
  console.log("Rider state is now 'at_pickup' (Ready for partner handover verification).");
}

main().catch(err => {
  console.error(err);
  process.exit(1);
});
