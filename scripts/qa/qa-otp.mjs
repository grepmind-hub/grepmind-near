import { createHmac } from 'node:crypto';

/** Consume one matching code through the loopback-only, scoped QA reader. */
export async function readQaOtp(challengeId, phoneE164, expiresAt) {
  const endpoint = process.env.QA_OTP_READER_URL;
  const runId = process.env.QA_OTP_RUN_ID;
  const runnerId = process.env.QA_OTP_RUNNER_ID;
  const secret = process.env.QA_OTP_RUNNER_SECRET;
  if (!endpoint || !runId || !runnerId || !secret) {
    throw new Error('Secure QA OTP reader configuration is required.');
  }
  const readerUrl = new URL(endpoint);
  if (readerUrl.protocol !== 'http:' || !['127.0.0.1', 'localhost'].includes(readerUrl.hostname) || readerUrl.username || readerUrl.password || readerUrl.search || readerUrl.hash) {
    throw new Error('QA OTP reader must use an authenticated loopback-only HTTP origin.');
  }
  if (!/^[0-9a-f-]{36}$/i.test(challengeId || '')) {
    throw new Error('OTP challenge ID is missing or invalid.');
  }
  if (typeof expiresAt !== 'string' || !Number.isFinite(Date.parse(expiresAt))) throw new Error('OTP challenge expiry is missing or invalid.');
  const scope = { challenge_id: challengeId, phone_e164: phoneE164, purpose: 'login', run_id: runId, expires_at: expiresAt };
  const capability = createHmac('sha256', secret)
    .update([runnerId, runId, challengeId, phoneE164, 'login', expiresAt].join('\0'))
    .digest('hex');
  const response = await fetch(`${readerUrl.origin}/v1/read`, {
    method: 'POST',
    headers: { 'content-type': 'application/json', authorization: `Bearer ${capability}`, 'x-qa-runner-id': runnerId },
    body: JSON.stringify(scope),
    signal: AbortSignal.timeout(5000),
  });
  if (!response.ok) throw new Error('Scoped private QA OTP retrieval failed.');
  const payload = await response.json();
  const code = payload?.code;
  if (!/^\d{6}$/.test(code)) throw new Error('Private QA reader returned an invalid OTP.');
  return code;
}
