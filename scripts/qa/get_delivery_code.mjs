import { readQaOtp } from "./qa-otp.mjs";

async function main() {
  const base = "http://127.0.0.1:18083/api/v1";
  const phone = "+919990000171";
  const orderId = process.argv[2] || "ba2ee85a-20de-4a2e-88a9-16eaef3080a6";

  const challengeRes = await fetch(`${base}/auth/otp/request`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ phone_e164: phone }),
  });
  const challenge = await challengeRes.json();
  const challengeId = challenge?.data?.challenge_id;
  console.log("Challenge:", challengeId);
  const otp = await readQaOtp(challengeId, phone, challenge?.data?.expires_at);
  console.log("OTP received:", otp);

  const verifyRes = await fetch(`${base}/auth/otp/verify`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ phone_e164: phone, otp_code: otp, challenge_id: challengeId }),
  });
  const verified = await verifyRes.json();
  const token = verified.data.access_token;
  console.log("Token acquired!");

  const codeRes = await fetch(`${base}/orders/${orderId}/delivery-code`, {
    method: "POST",
    headers: { "Authorization": `Bearer ${token}` }
  });
  const codeData = await codeRes.json();
  console.log("DELIVERY CODE RESULT:", JSON.stringify(codeData));
}

main().catch(err => console.error("Error:", err));
