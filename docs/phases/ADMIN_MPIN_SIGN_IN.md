# Admin Web device PIN sign-in

Admin Web can offer a six-digit Grepmind PIN after OTP authentication. Enrollment consumes proof from an active Admin session issued through OTP on the configured portal origin within the previous five minutes.

Returning sign-in requires the PIN and the browser's random, secure, HTTP-only cookie. PostgreSQL stores a digest of the device credential and a bcrypt hash of the PIN combined with that credential. The backend checks the active Admin role at sign-in and issues the standard rotating session. A browser enrollment expires after 30 days. Five consecutive failures lock the enrollment. A fresh OTP login can replace it, including from another browser. Each Admin has one enrolled browser at a time.

Normal sign-out ends the application session and retains the enrolled-browser credential. Admins can skip enrollment on shared computers. Losing the browser cookie, a lockout, or expiry returns the Admin to OTP.

## Isolated QA setup

Apply migration `041_admin_device_mpin.sql` to a disposable QA database. Configure `ADMIN_MPIN_ORIGIN` on the isolated API with the exact Admin portal origin, for example `http://localhost:18300`. Use that same origin in the browser. HTTPS is required for non-loopback origins. When the setting is absent, the OTP flow remains available and the PIN routes refuse enrollment and sign-in. Production activation requires its own rollout and working OTP recovery.

## Verification

The Go auth suite passed against a disposable tmpfs PostGIS database. The MPIN lifecycle test exercised actual OTP verification, browser enrollment, origin rejection, denial without the browser credential, five-attempt lockout, OTP recovery, prior-browser invalidation, and denial after Admin role removal. Go vet, the Admin production build, and the Playwright flow with mocked HTTP responses passed. Three commerce API integration failures reproduced with the MPIN changes removed. End-to-end Admin acceptance against an MPIN-enabled QA API remains open.

## Returning browser behavior

The headed Windows QA runner now keeps a dedicated local Chrome profile for each Admin identity and portal origin when invoked with `-KeepBrowserOpen`. After the first OTP and PIN enrollment, rerunning the command or reopening the login page in the same profile opens PIN sign-in without requesting OTP. Use `-UseOtp` with the same runner when OTP fallback is needed. An active enrollment for the same account suppresses repeated PIN setup after a successful fallback OTP.

The disposable Playwright test enrolled a PIN, closed Chromium, reopened the same profile, and signed in with PIN without any OTP request. The Go/PostgreSQL auth suite checked same-browser OTP fallback, lockout recovery, and replacement. The API fix was rolled out to isolated QA without a migration or changes to active browser enrollments.
