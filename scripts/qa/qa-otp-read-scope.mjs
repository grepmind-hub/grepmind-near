import { readFile } from 'node:fs/promises';
import { readQaOtp } from './qa-otp.mjs';

// Trusted-host QA utility. Challenge metadata arrives through a private file;
// only the one-time code is written to stdout for the caller to hold in memory.
// Never run this utility in production or emit/capture its stdout in CI logs.
const inputPath = process.argv[2];
if (!inputPath) throw new Error('A challenge-scope file is required.');
const scope = JSON.parse(await readFile(inputPath, 'utf8'));
const code = await readQaOtp(
  scope.challenge_id,
  scope.phone_e164,
  scope.expires_at,
);
process.stdout.write(code);
