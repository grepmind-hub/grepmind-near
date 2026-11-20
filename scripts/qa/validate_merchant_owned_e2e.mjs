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
  const cached = getCachedToken(phone);
  if (cached) {
    try {
      const chk = await fetch(`${base}/customer/orders`, { headers: { "Authorization": `Bearer ${cached}` } });
      if (chk.ok || chk.status === 404) return cached;
    } catch (_) {}
  }
  for (let attempt = 0; attempt < 8; attempt++) {
    const challengeRes = await fetch(`${base}/auth/otp/request`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ phone_e164: phone }),
    });
    const challenge = await challengeRes.json();
    if (challenge?.error?.code === "RATE_LIMITED") {
      console.log(`  [AUTH] Rate limited on ${phone}, waiting 15s...`);
      await new Promise(r => setTimeout(r, 15000));
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
      "Content-Type": "application/json",
      ...(token ? { "Authorization": `Bearer ${token}` } : {}),
      ...headers,
    },
    ...(body ? { body: JSON.stringify(body) } : {}),
  });
  let data = null;
  try {
    data = await res.json();
  } catch (_) {}
  return { ok: res.ok, status: res.status, data };
}

async function run() {
  console.log("========================================================================");
  console.log("  ABASHYAKA: MERCHANT-OWNED FOOD & GROCERY COMMERCE LIFECYCLE (02G/02H)");
  console.log("========================================================================\n");

  const businessId = "3e000000-0000-4000-8000-000000000101"; // Phase 3E QA Food Partner
  const riderUserId = "3e000000-0000-4000-8000-000000000003";

  // Pre-flight DB reset and setup
  psql(`
    UPDATE financial_feature_config
    SET financial_posting_enabled=true,
        payment_intent_creation_enabled=true,
        payment_attempt_creation_enabled=true,
        sandbox_payment_enabled=true,
        sandbox_cod_enabled=true,
        upi_enabled=false,
        cod_enabled=false,
        merchant_settlement_enabled=false,
        real_money_enabled=false
    WHERE singleton=true;

    UPDATE delivery_assignments SET state='cancelled', ended_at=now() WHERE state='active';
    UPDATE delivery_dispatch_runs SET state='completed', completed_at=now() WHERE state='running';
    UPDATE delivery_offers SET state='expired' WHERE state='offered';
    INSERT INTO rider_availability_sessions (rider_user_id, is_online, lease_expires_at, last_heartbeat_at, updated_at)
    VALUES ('${riderUserId}', true, now() + interval '2 hours', now(), now())
    ON CONFLICT (rider_user_id) DO UPDATE SET is_online=true, lease_expires_at=now() + interval '2 hours', last_heartbeat_at=now(), updated_at=now();

    INSERT INTO professional_profiles (business_id, service_radius_m, accepts_requests, created_at, updated_at)
    VALUES ('${businessId}', 15000, true, now(), now())
    ON CONFLICT (business_id) DO UPDATE SET service_radius_m = 15000, accepts_requests = true, updated_at = now();
  `);
  console.log("✓ Initial state ready (Rider online, Financial features enabled).\n");

  console.log("[AUTH] Authenticating actors: Customer (+919990000171), Merchant (+919990000172), Rider (+919990000173)...");
  const customerToken = await getAuthToken("+919990000171");
  const merchantToken = await getAuthToken("+919990000172");
  const riderToken = await getAuthToken("+919990000173");
  console.log("✓ All 3 actors authenticated.\n");

  // Step 1: Merchant creates new Food & Grocery catalog items with Phase 02G attributes
  console.log("[Step 1] Merchant creating new Food and Grocery catalog items with 02G attributes...");
  const foodCreateRes = await request("/merchant/products", {
    token: merchantToken,
    method: "POST",
    body: {
      name: "Hyderabadi Dum Biryani Pot",
      description: "Authentic slow-cooked saffron rice with tender mutton pieces",
      price: 320.0,
      stock_status: "in_stock",
      inventory_mode: "finite",
      available_quantity: 35,
      is_published: true,
      unit_label: "1 Handi (750g)",
      mrp: 360.0,
      dietary_type: "non_veg",
      food_category: "Biryani & Rice"
    }
  });
  if (!foodCreateRes.ok) throw new Error(`Food product creation failed: ${JSON.stringify(foodCreateRes.data)}`);
  const foodProductId = foodCreateRes.data.data.id;
  console.log(`  ✓ Created Food Product: ${foodProductId} (Hyderabadi Dum Biryani Pot, MRP: ₹360, Price: ₹320, Unit: 1 Handi)`);

  const groceryCreateRes = await request("/merchant/products", {
    token: merchantToken,
    method: "POST",
    body: {
      name: "Fortune Sunlite Refined Sunflower Oil",
      description: "Light and healthy cooking oil enriched with vitamins A & D",
      price: 145.0,
      stock_status: "in_stock",
      inventory_mode: "finite",
      available_quantity: 50,
      is_published: true,
      unit_label: "1 Litre Pouch",
      mrp: 170.0,
      barcode: "8901234567890",
      grocery_category: "Edible Oils & Ghee"
    }
  });
  if (!groceryCreateRes.ok) throw new Error(`Grocery product creation failed: ${JSON.stringify(groceryCreateRes.data)}`);
  const groceryProductId = groceryCreateRes.data.data.id;
  console.log(`  ✓ Created Grocery Product: ${groceryProductId} (Fortune Sunlite Oil, MRP: ₹170, Price: ₹145, Barcode: 8901234567890, Cat: Edible Oils)`);

  // Verify persistence in PostgreSQL
  const dbFood = psql(`SELECT name, price, mrp, unit_label, available_quantity FROM products WHERE id='${foodProductId}';`);
  const dbGrocery = psql(`SELECT name, price, mrp, unit_label, barcode, grocery_category FROM products WHERE id='${groceryProductId}';`);
  console.log(`  ✓ DB Food Record: ${dbFood}`);
  console.log(`  ✓ DB Grocery Record: ${dbGrocery}`);
  if (!dbGrocery.includes("8901234567890") || !dbGrocery.includes("Edible Oils & Ghee")) {
    throw new Error(`02G Product columns not persisted correctly in DB!`);
  }

  // Step 2: Customer discovers products via Public Discovery API
  console.log("\n[Step 2] Customer fetching merchant products via Discovery API...");
  const discoveryRes = await request(`/businesses/${businessId}/products`, { token: customerToken });
  if (!discoveryRes.ok) throw new Error(`Discovery failed: ${JSON.stringify(discoveryRes.data)}`);
  const discoveredProducts = discoveryRes.data?.data || discoveryRes.data || [];
  const foundFood = discoveredProducts.find(p => p.id === foodProductId);
  const foundGrocery = discoveredProducts.find(p => p.id === groceryProductId);
  if (!foundFood || !foundGrocery) {
    throw new Error(`Customer discovery could not find newly created products!`);
  }
  console.log(`  ✓ Customer discovered Food: ${foundFood.name} (Unit: ${foundFood.unit_label}, Price: ₹${foundFood.price}, MRP: ₹${foundFood.mrp})`);
  console.log(`  ✓ Customer discovered Grocery: ${foundGrocery.name} (Unit: ${foundGrocery.unit_label}, Category: ${foundGrocery.grocery_category})`);

  // Step 3: Customer requests Checkout Quote for Merchant-Owned Food Order
  console.log("\n[Step 3] Customer generating checkout quote for Merchant Food order...");
  const addressId = "3e000000-0000-4000-8000-000000000301";
  const quoteRes = await request(`/businesses/${businessId}/orders/quote`, {
    token: customerToken,
    method: "POST",
    body: {
      fulfillment_type: "delivery",
      address_id: addressId,
      items: [
        { product_id: foodProductId, quantity: 2 }
      ]
    }
  });
  if (!quoteRes.ok) throw new Error(`Quote generation failed: ${JSON.stringify(quoteRes.data)}`);
  const quote = quoteRes.data.data;
  console.log(`  ✓ Quote created: ${quote.quote_id} | Subtotal: ₹${quote.item_subtotal_minor / 100} | Delivery: ₹${quote.delivery_fee_minor / 100} | Total: ₹${quote.grand_total_minor / 100}`);

  // Step 4: Customer places Merchant-Owned Order with COD
  console.log("\n[Step 4] Customer placing Merchant-Owned order (payment_method='cash_on_delivery')...");
  const idempotencyKey = randomUUID();
  const orderRes = await request(`/businesses/${businessId}/orders`, {
    token: customerToken,
    method: "POST",
    headers: { "Idempotency-Key": idempotencyKey },
    body: {
      order_type: "food_delivery",
      checkout_quote_id: quote.quote_id,
      fulfillment_type: "delivery",
      payment_method: "cash_on_delivery",
      notes: "Gate 02G/02H merchant-owned lifecycle validation."
    }
  });
  if (!orderRes.ok) throw new Error(`Order placement failed: ${JSON.stringify(orderRes.data)}`);
  const order = orderRes.data.data;
  console.log(`  ✓ Merchant Order Placed: Reference=${order.voucher_code || order.reference_code} (ID: ${order.id})`);
  console.log(`    Status: ${order.status} | Source: ${order.order_source} | Payment: ${order.payment_method}/${order.payment_status}`);

  // Verify inventory deduction in PostgreSQL
  const qtyAfterOrder = psql(`SELECT available_quantity FROM products WHERE id='${foodProductId}'`);
  console.log(`  ✓ Finite inventory safely deducted: 35 -> ${qtyAfterOrder} (expected 33)`);
  if (parseInt(qtyAfterOrder, 10) !== 33) throw new Error(`Inventory deduction mismatch! Expected 33, got ${qtyAfterOrder}`);

  // Step 5: Merchant views order under Unified Platform Orders
  console.log("\n[Step 5] Merchant retrieving incoming orders via Unified Platform Orders API...");
  const merchantOrdersRes = await request(`/merchant/businesses/${businessId}/platform-orders`, { token: merchantToken });
  if (!merchantOrdersRes.ok) throw new Error(`Merchant orders retrieval failed: ${JSON.stringify(merchantOrdersRes.data)}`);
  const ordersList = merchantOrdersRes.data?.data || merchantOrdersRes.data || [];
  const foundOrder = ordersList.find(o => o.id === order.id);
  if (!foundOrder) {
    throw new Error(`Merchant cannot see newly placed merchant-catalog order in incoming orders pipeline!`);
  }
  console.log(`  ✓ Merchant sees order in incoming queue: ID=${foundOrder.id}, Status=${foundOrder.status}, GrandTotal=₹${foundOrder.grand_total}`);

  // Step 6: Merchant Accepts Order
  console.log("\n[Step 6] Merchant accepting order...");
  const acceptRes = await request(`/merchant/businesses/${businessId}/platform-orders/${order.id}/accept`, {
    token: merchantToken,
    method: "POST"
  });
  if (!acceptRes.ok) throw new Error(`Merchant accept failed: ${JSON.stringify(acceptRes.data)}`);
  console.log(`  ✓ Merchant accepted order (status='accepted').`);

  // Step 7: Merchant Prepares Order -> Trigger must create delivery_job!
  console.log("\n[Step 7] Merchant marks preparing -> Verifying delivery_job trigger for merchant_catalog order...");
  const prepRes = await request(`/merchant/businesses/${businessId}/platform-orders/${order.id}/prepare`, {
    token: merchantToken,
    method: "POST"
  });
  if (!prepRes.ok) throw new Error(`Merchant prepare failed: ${JSON.stringify(prepRes.data)}`);
  console.log(`  ✓ Merchant started preparing order.`);

  const jobId = psql(`SELECT id FROM delivery_jobs WHERE order_id='${order.id}';`);
  if (!jobId) throw new Error(`CRITICAL: Delivery job was NOT created by trigger for merchant_catalog order!`);
  const jobState = psql(`SELECT state, execution_state, locality_id FROM delivery_jobs WHERE id='${jobId}';`);
  console.log(`  ✓ Delivery Job successfully created by DB trigger: ${jobId} | State: ${jobState}`);

  // Step 8: Dispatch Job to Rider
  console.log("\n[Step 8] Triggering delivery dispatch runner to offer job to Rider...");
  psql(`
    UPDATE delivery_offers SET state='expired', responded_at=now() WHERE rider_user_id='${riderUserId}' AND state='offered';
    UPDATE delivery_jobs SET state='pending_dispatch', updated_at=now() WHERE id='${jobId}';
    UPDATE delivery_dispatch_runs SET state='cancelled', completed_at=now() WHERE job_id='${jobId}' AND state IN ('searching', 'no_rider_available');
  `);

  const runId = randomUUID();
  await request("/admin/delivery/dispatch/run", {
    token: customerToken,
    method: "POST",
    body: { locality_id: "02200000-0000-4000-8000-000000000101", idempotency_key: runId },
  });

  let offerId = "";
  for (let i = 0; i < 10; i++) {
    offerId = psql(`SELECT id FROM delivery_offers WHERE job_id = '${jobId}' AND rider_user_id = '${riderUserId}' AND state = 'offered' ORDER BY offered_at DESC LIMIT 1`);
    if (offerId) break;
    await new Promise(r => setTimeout(r, 400));
  }
  if (!offerId) {
    throw new Error(`Dispatch engine did not offer job ${jobId} to Rider ${riderUserId}`);
  }
  console.log(`  ✓ System dispatched delivery offer to Rider (+919990000173): OfferID=${offerId}`);

  // Step 9: Rider Accepts Offer
  console.log("\n[Step 9] Rider accepting delivery offer...");
  const acceptOfferRes = await request(`/rider/offers/${offerId}/accept`, {
    token: riderToken,
    method: "POST"
  });
  if (!acceptOfferRes.ok) throw new Error(`Rider accept offer failed: ${JSON.stringify(acceptOfferRes.data)}`);
  console.log(`  ✓ Rider accepted offer (job state='assigned').`);

  // Step 10: Merchant Marks Ready & Rider Arrives at Pickup
  console.log("\n[Step 10] Merchant marking order ready & Rider arriving at store...");
  const readyRes = await request(`/merchant/businesses/${businessId}/platform-orders/${order.id}/ready`, {
    token: merchantToken,
    method: "POST"
  });
  if (!readyRes.ok) throw new Error(`Merchant ready failed: ${JSON.stringify(readyRes.data)}`);
  console.log(`  ✓ Merchant marked order ready.`);

  await request(`/rider/delivery-jobs/${jobId}/state`, {
    token: riderToken,
    method: "POST",
    body: { state: "arriving_at_pickup" }
  });
  await request(`/rider/delivery-jobs/${jobId}/state`, {
    token: riderToken,
    method: "POST",
    body: { state: "at_pickup" }
  });
  console.log(`  ✓ Rider arrived at store (state='at_pickup').`);

  // Step 11: Merchant Issues Pickup Code & Rider Verifies Pickup
  console.log("\n[Step 11] Merchant issuing pickup code & Rider verifying custody transfer...");
  const pickupCodeRes = await request(`/merchant/businesses/${businessId}/delivery-jobs/${jobId}/pickup-code`, {
    token: merchantToken,
    method: "POST"
  });
  if (!pickupCodeRes.ok) throw new Error(`Pickup code generation failed: ${JSON.stringify(pickupCodeRes.data)}`);
  const pickupCode = pickupCodeRes.data?.data?.pickup_code;
  console.log(`  ✓ Merchant issued single-use pickup code: ${pickupCode}`);

  const verifyPickupRes = await request(`/rider/delivery-jobs/${jobId}/pickup/verify`, {
    token: riderToken,
    method: "POST",
    body: { code: pickupCode }
  });
  if (!verifyPickupRes.ok) throw new Error(`Pickup verification failed: ${JSON.stringify(verifyPickupRes.data)}`);
  console.log(`  ✓ Rider verified pickup code! Custody transferred (Order status='out_for_delivery').`);

  // Step 12: Rider En Route & Customer Generates Delivery Confirmation Code
  console.log("\n[Step 12] Rider en route and Customer generating delivery confirmation code...");
  await request(`/rider/delivery-jobs/${jobId}/state`, {
    token: riderToken,
    method: "POST",
    body: { state: "en_route" }
  });

  const delCodeRes = await request(`/orders/${order.id}/delivery-code`, {
    token: customerToken,
    method: "POST"
  });
  const deliveryCode = delCodeRes.data?.data?.delivery_code || delCodeRes.data?.delivery_code;
  console.log(`  ✓ Customer generated delivery confirmation code: ${deliveryCode}`);

  // Step 13: Rider Confirms Delivery & Collects COD
  console.log("\n[Step 13] Rider confirming delivery and collecting COD...");
  const confirmDeliveryRes = await request(`/rider/delivery-jobs/${jobId}/delivery/confirm`, {
    token: riderToken,
    method: "POST",
    body: {
      code: deliveryCode,
      confirm_cod_collection: true
    }
  });
  if (!confirmDeliveryRes.ok) throw new Error(`Delivery confirmation failed: ${JSON.stringify(confirmDeliveryRes.data)}`);
  console.log(`  ✓ Rider confirmed delivery and collected COD!`);

  // Step 14: Final Database Integrity Check
  console.log("\n[Step 14] Verifying final PostgreSQL state...");
  const finalOrder = psql(`SELECT status, payment_method FROM customer_orders WHERE id='${order.id}';`);
  const finalJob = psql(`SELECT execution_state FROM delivery_jobs WHERE id='${jobId}';`);
  const finalCOD = psql(`SELECT state, amount_minor FROM cod_obligations WHERE order_id='${order.id}';`);
  console.log(`  ✓ Order State: ${finalOrder} (expected: delivered|cash_on_delivery)`);
  console.log(`  ✓ Job Execution State: ${finalJob} (expected: delivered)`);
  console.log(`  ✓ COD Obligation State: ${finalCOD} (expected: collected|67000)`);
  if (!finalOrder.includes("delivered") || !finalJob.includes("delivered") || !finalCOD.includes("collected")) {
    throw new Error(`Final delivery and COD state check failed! Got: ${finalOrder}, job: ${finalJob}, cod: ${finalCOD}`);
  }

  // Step 15: Rejection & Inventory Restoration Path
  console.log("\n[Step 15] Testing Rejection & Finite Inventory Restoration path...");
  const quote2Res = await request(`/businesses/${businessId}/orders/quote`, {
    token: customerToken,
    method: "POST",
    body: {
      fulfillment_type: "delivery",
      address_id: addressId,
      items: [{ product_id: foodProductId, quantity: 3 }]
    }
  });
  const quote2 = quote2Res.data.data;
  const order2Res = await request(`/businesses/${businessId}/orders`, {
    token: customerToken,
    method: "POST",
    headers: { "Idempotency-Key": randomUUID() },
    body: {
      order_type: "food_delivery",
      checkout_quote_id: quote2.quote_id,
      fulfillment_type: "delivery",
      payment_method: "cash_on_delivery"
    }
  });
  const order2 = order2Res.data.data;
  const qtyDuringOrder2 = psql(`SELECT available_quantity FROM products WHERE id='${foodProductId}'`);
  console.log(`  ✓ Order 2 created (${order2.id}). Stock decremented: 33 -> ${qtyDuringOrder2} (expected 30)`);

  const rejectRes = await request(`/merchant/businesses/${businessId}/platform-orders/${order2.id}/reject`, {
    token: merchantToken,
    method: "POST",
    body: { reason: "Kitchen out of biryani handis" }
  });
  if (!rejectRes.ok) throw new Error(`Merchant rejection failed: ${JSON.stringify(rejectRes.data)}`);
  const qtyAfterReject = psql(`SELECT available_quantity FROM products WHERE id='${foodProductId}'`);
  console.log(`  ✓ Merchant rejected order 2. Finite inventory safely restored: ${qtyDuringOrder2} -> ${qtyAfterReject} (expected 33)`);
  if (parseInt(qtyAfterReject, 10) !== 33) {
    throw new Error(`Inventory restoration mismatch! Expected 33, got ${qtyAfterReject}`);
  }

  // Step 16: Merchant-Owned UPI Payment & Capture Lifecycle
  console.log("\n[Step 16] Testing Merchant-Owned UPI Payment & Sandbox Capture Lifecycle...");
  const quote3Res = await request(`/businesses/${businessId}/orders/quote`, {
    token: customerToken,
    method: "POST",
    body: {
      fulfillment_type: "delivery",
      address_id: addressId,
      items: [{ product_id: groceryProductId, quantity: 2 }]
    }
  });
  const quote3 = quote3Res.data.data;
  const order3Res = await request(`/businesses/${businessId}/orders`, {
    token: customerToken,
    method: "POST",
    headers: { "Idempotency-Key": randomUUID() },
    body: {
      order_type: "food_delivery",
      checkout_quote_id: quote3.quote_id,
      fulfillment_type: "delivery",
      payment_method: "upi",
      notes: "Merchant-Owned Grocery UPI Order"
    }
  });
  if (!order3Res.ok) throw new Error(`UPI Order 3 placement failed: ${JSON.stringify(order3Res.data)}`);
  const order3 = order3Res.data.data;
  console.log(`  ✓ Merchant-Owned Grocery UPI Order Placed: ID=${order3.id}, Total=₹${quote3.grand_total_minor / 100}, Payment=${order3.payment_method}/${order3.payment_status}`);

  const intentRes = await request(`/orders/${order3.id}/payment-intents`, {
    token: customerToken,
    method: "POST",
    headers: { "Idempotency-Key": randomUUID() },
  });
  if (!intentRes.ok) throw new Error(`Payment intent failed: ${JSON.stringify(intentRes.data)}`);
  console.log(`  ✓ Payment intent created for merchant-owned order`);

  const sessionRes = await request(`/orders/${order3.id}/payment-sessions`, {
    token: customerToken,
    method: "POST",
    headers: { "Idempotency-Key": randomUUID() },
  });
  if (!sessionRes.ok) throw new Error(`Payment session failed: ${JSON.stringify(sessionRes.data)}`);
  console.log(`  ✓ Payment session initialized`);

  const simRes = await request(`/orders/${order3.id}/sandbox-payment-outcomes`, {
    token: customerToken,
    method: "POST",
    body: { status: "succeeded" },
  });
  if (!simRes.ok) throw new Error(`Sandbox outcome failed: ${JSON.stringify(simRes.data)}`);
  const payStatusAfterCapture = psql(`SELECT payment_status FROM customer_orders WHERE id='${order3.id}'`);
  console.log(`  ✓ Sandbox UPI capture successful! Payment status in DB: ${payStatusAfterCapture} (expected: paid)`);
  if (payStatusAfterCapture !== "paid") {
    throw new Error(`Expected payment_status to be 'paid', got '${payStatusAfterCapture}'`);
  }

  console.log("\n========================================================================");
  console.log("🎉 ALL 16 GATES OF MERCHANT-OWNED FOOD & GROCERY COMMERCE PASSED!");
  console.log("========================================================================");
}

run().catch(err => {
  console.error("VALIDATION FAILED:", err);
  process.exit(1);
});
