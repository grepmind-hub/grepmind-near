import { readQaOtp } from "./qa-otp.mjs";
import { execSync } from "child_process";

const base = process.env.QA_API_BASE || "http://127.0.0.1:18083/api/v1";

function psql(query) {
  const cmd = `docker exec grepmind_3e_qa_db psql -U qa3e -d grepmind_3e_qa -t -A -c "${query.replace(/"/g, '\\"')}"`;
  return execSync(cmd, { encoding: "utf-8" }).trim();
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
    return verified.data.access_token;
  }
  throw new Error(`Exhausted OTP attempts for ${phone}`);
}

async function runGate2() {
  console.log("=== GATE 2: MERCHANT CATALOG PERSISTENCE & ISOLATION ===");

  console.log("\n[Step 0] Authenticating Merchant (+919990000172) & Customer (+919990000171)...");
  const merchantToken = await getAuthToken("+919990000172");
  const customerToken = await getAuthToken("+919990000171");
  console.log("✓ Tokens obtained successfully.");

  // 1. Create product
  console.log("\n[Step 1] Creating product via Merchant API...");
  const createRes = await fetch(`${base}/merchant/products`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "Authorization": `Bearer ${merchantToken}`
    },
    body: JSON.stringify({
      name: "QA Mustard Oil Cold Pressed 1L",
      description: "100% pure cold pressed mustard oil for traditional cooking",
      price: 195.0,
      stock_status: "in_stock",
      inventory_mode: "finite",
      available_quantity: 25,
      is_published: true
    })
  });
  const createData = await createRes.json();
  if (!createRes.ok || !createData?.data?.id) {
    throw new Error(`Failed to create product: ${JSON.stringify(createData)}`);
  }
  const productId = createData.data.id;
  const businessId = "3e000000-0000-4000-8000-000000000101";
  console.log(`✓ Product created successfully: ID=${productId}, Biz=${businessId}`);

  // 2. Confirm database persistence
  console.log("\n[Step 2] Confirming database persistence...");
  const dbRow = psql(`SELECT id, name, price, stock_status, inventory_mode, available_quantity, is_published FROM products WHERE id='${productId}';`);
  console.log(`  DB Record: ${dbRow}`);
  if (!dbRow.includes("QA Mustard Oil Cold Pressed 1L") || !dbRow.includes("195.00") || !dbRow.includes("25")) {
    throw new Error(`Database record does not match created attributes! Got: ${dbRow}`);
  }
  console.log("✓ Database persistence verified.");

  // 3. Edit price and stock
  console.log("\n[Step 3] Editing price (195 -> 210) and stock (25 -> 30)...");
  const patchRes = await fetch(`${base}/merchant/products/${productId}`, {
    method: "PATCH",
    headers: {
      "Content-Type": "application/json",
      "Authorization": `Bearer ${merchantToken}`
    },
    body: JSON.stringify({
      price: 210.0,
      inventory_mode: "finite",
      available_quantity: 30
    })
  });
  const patchData = await patchRes.json();
  if (!patchRes.ok) {
    throw new Error(`Failed to patch product: ${JSON.stringify(patchData)}`);
  }
  console.log("✓ PATCH returned HTTP 200.");

  // 4 & 5. Refresh & confirm values
  console.log("\n[Step 4 & 5] Confirming updated values via API and DB...");
  const getRes = await fetch(`${base}/merchant/products`, {
    headers: { "Authorization": `Bearer ${merchantToken}` }
  });
  const listData = await getRes.json();
  const found = (listData?.data || []).find(p => p.id === productId);
  if (!found || found.price !== 210 || found.available_quantity !== 30) {
    throw new Error(`Merchant product list verification failed: ${JSON.stringify(found)}`);
  }
  const dbUpdated = psql(`SELECT price, available_quantity, stock_status FROM products WHERE id='${productId}';`);
  console.log(`  DB Updated: ${dbUpdated}`);
  if (!dbUpdated.includes("210.00") || !dbUpdated.includes("30")) {
    throw new Error(`Database does not reflect updated price/qty! Got: ${dbUpdated}`);
  }
  console.log("✓ Price 210.00 and stock 30 verified in API and PostgreSQL.");

  // 6. Test stock boundaries and invalid quantities
  console.log("\n[Step 6] Testing stock boundaries and invalid quantities...");
  // 6a: Negative quantity
  const negRes = await fetch(`${base}/merchant/products/${productId}`, {
    method: "PATCH",
    headers: {
      "Content-Type": "application/json",
      "Authorization": `Bearer ${merchantToken}`
    },
    body: JSON.stringify({
      inventory_mode: "finite",
      available_quantity: -5
    })
  });
  console.log(`  Negative quantity HTTP status: ${negRes.status}`);
  if (negRes.status !== 400) {
    throw new Error(`Expected HTTP 400 for negative quantity, got ${negRes.status}`);
  }
  console.log("✓ Negative quantity rejected with HTTP 400 VALIDATION_ERROR.");

  // 6b: Zero quantity transitions to out_of_stock
  const zeroRes = await fetch(`${base}/merchant/products/${productId}`, {
    method: "PATCH",
    headers: {
      "Content-Type": "application/json",
      "Authorization": `Bearer ${merchantToken}`
    },
    body: JSON.stringify({
      inventory_mode: "finite",
      available_quantity: 0
    })
  });
  if (!zeroRes.ok) throw new Error("Failed to set quantity 0");
  const dbZero = psql(`SELECT available_quantity, stock_status FROM products WHERE id='${productId}';`);
  console.log(`  DB at qty 0: ${dbZero}`);
  if (!dbZero.includes("out_of_stock")) {
    throw new Error(`Expected out_of_stock for qty 0, got ${dbZero}`);
  }
  console.log("✓ Quantity 0 automatically transitions stock_status to out_of_stock.");

  // 6c: Restore to 5 (limited)
  await fetch(`${base}/merchant/products/${productId}`, {
    method: "PATCH",
    headers: {
      "Content-Type": "application/json",
      "Authorization": `Bearer ${merchantToken}`
    },
    body: JSON.stringify({
      inventory_mode: "finite",
      available_quantity: 5,
      stock_status: "limited"
    })
  });

  // 7. Test another merchant / customer inability to modify the product
  console.log("\n[Step 7] Testing unauthorized modification (Customer attempting PATCH)...");
  const unauthRes = await fetch(`${base}/merchant/products/${productId}`, {
    method: "PATCH",
    headers: {
      "Content-Type": "application/json",
      "Authorization": `Bearer ${customerToken}`
    },
    body: JSON.stringify({ price: 1.0 })
  });
  console.log(`  Unauthorized PATCH HTTP status: ${unauthRes.status}`);
  if (unauthRes.status !== 403 && unauthRes.status !== 404) {
    throw new Error(`Expected HTTP 403 or 404 for unauthorized PATCH, got ${unauthRes.status}`);
  }
  console.log("✓ Unauthorized product mutation blocked with HTTP 403/404.");

  // 8. Confirm Customer discovery reflects only eligible published products
  console.log("\n[Step 8] Verifying Customer discovery reflects published state...");
  const pubRes = await fetch(`${base}/businesses/${businessId}/products`);
  const pubData = await pubRes.json();
  const pubFound = (pubData?.data || []).find(p => p.id === productId);
  if (!pubFound) throw new Error("Published product not visible in public business discovery!");
  console.log("✓ Published product is visible in customer discovery.");

  // Unpublish
  console.log("  Unpublishing product (making draft)...");
  await fetch(`${base}/merchant/products/${productId}`, {
    method: "PATCH",
    headers: {
      "Content-Type": "application/json",
      "Authorization": `Bearer ${merchantToken}`
    },
    body: JSON.stringify({ is_published: false })
  });

  const unpubRes = await fetch(`${base}/businesses/${businessId}/products`);
  const unpubData = await unpubRes.json();
  const unpubFound = (unpubData?.data || []).find(p => p.id === productId);
  if (unpubFound) throw new Error("Unpublished product should NOT be visible in customer discovery!");
  console.log("✓ Unpublished product is excluded from customer discovery.");

  // Cleanup
  console.log("\n[Cleanup] Deleting test product...");
  const delRes = await fetch(`${base}/merchant/products/${productId}`, {
    method: "DELETE",
    headers: { "Authorization": `Bearer ${merchantToken}` }
  });
  if (!delRes.ok) throw new Error("Failed to delete test product");
  const dbCheck = psql(`SELECT count(*) FROM products WHERE id='${productId}';`);
  if (parseInt(dbCheck, 10) !== 0) throw new Error("Product was not deleted from database!");
  console.log("✓ Test product deleted and database cleaned up.");

  console.log("\n🎉 GATE 2 COMPLETE: ALL 8 PERSISTENCE & SECURITY CHECKS PASSED!");
}

runGate2().catch(err => {
  console.error("GATE 2 FAILED:", err);
  process.exit(1);
});
