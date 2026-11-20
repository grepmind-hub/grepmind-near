# Admin portal combined QA acceptance

**PASS for OTP, browser PIN and the Phase 5C–5E read-only Admin finance views on 16 November 2026.**

## Running QA accounts

| Identity | Application access | Running QA state |
| --- | --- | --- |
| `+91 99900 00174` | Platform Admin | Active Admin, enrolled PIN, no active finance grant |
| `+91 00000 00000` | Protected primary super-admin | Active protected Admin record, eligible for platform role management; excluded from synthetic OTP login testing |

Both accounts are stored with the `admin` role. The backend separately checks the protected primary identity for role-management operations. Regular Admins require an explicit finance grant. The running portal at port 18302 was inspected read-only. It contains no payment, reconciliation, or settlement fixtures.

## Combined disposable run

A fresh tmpfs PostgreSQL database with migrations 001–041, the current isolated API image, the Admin production build, and a private OTP inbox served one combined browser run. Two independent synthetic Admins approved only `finance.read` for the test account. The browser completed actual OTP verification and PIN enrollment, signed out, and signed back in by PIN. Its user-access response returned `can_manage_roles=false`.

The browser loaded all four Finance Overview sections with live API responses. The requested refund was ₹90.00 on sandbox order `GN-D039766F`. COD order `GN-B18B7EE5` produced a verified ₹280.00 remittance, a ₹199.50 payable, and a ₹199.50 reconciled settlement simulation. Payment Tracking opened the captured order and showed a succeeded attempt with a matched reconciliation event. The queue listed outstanding order `GN-7C97A0D8` and retained the historical amount mismatch for `GN-50494859`. The first queue row opened the exact order's tracking view.

Read-only PostgreSQL checks found one active browser enrollment, one independently approved read grant, one record in each of the four overview panels, and six balanced journals. Payout transfers counted zero and live money, UPI, COD, settlement and payout flags stayed disabled. Anonymous and Customer queue requests were denied. The underlying synthetic commerce workflows ran through application APIs. Admin Web was the browser acceptance scope.

The synthetic test account and its PIN belong to the disposable run. This acceptance does not authorize a production deploy, production OTP or payment provider activation, or the separate pending Phase 4F and 5B gates.

[Combined Admin browser evidence](evidence/admin-portal-acceptance/finance-overview.png).

## Platform Admin read-access policy update

On 16 November 2026, read-only Admin finance endpoints were changed to authorize active Platform Admins directly. The previous individual `finance.read` grants in the earlier acceptance runs were used under the former policy. Read endpoints now show stored records even when the sandbox write features are disabled. Existing financial mutations, reconciliation actions, grant management, and role changes retain their authorization and separation-of-duties checks.

The Admin production build and API image were deployed to the running isolated QA portal at port 18302. Two Playwright checks passed, including actual OTP login for the existing synthetic Platform Admin, HTTP 200 for all four Finance Overview endpoints and the reconciliation queue, and HTTP 403 for payable accrual. The disposable PostgreSQL authorization regression confirmed Customer denial and revocation after removal of the Admin role. Go tests and vet passed. The running QA database retained zero active finance grants and no sample finance records.
