# Google Play Launch Checklist

Status at audit: not release ready. This is an engineering checklist, not legal advice. Google Play policies and Indian legal requirements change; verify current official Play Console requirements and obtain qualified advice before publishing.

## Android build and release identity

- [ ] Replace `applicationId = "local.grepmind.grepmind_mobile"` with owned production application ID before first public release.
- [ ] Set user-facing app label, launcher assets, version name/code and supported SDK targets.
- [ ] Configure a dedicated upload/release signing key outside the repository and document secure custody, backup and Play App Signing enrollment.
- [ ] Replace release debug signing in `apps/mobile/android/app/build.gradle.kts` with release signing. Verify release APK/AAB signature and reproducible CI artifact.
- [ ] Replace `YOUR_GOOGLE_MAPS_API_KEY_HERE`; restrict the key by package name/signing certificate and allowed APIs, set quota/billing alerts, and avoid exposing server keys.
- [ ] Run `flutter build appbundle --release`, install a signed internal-test artifact, check startup, deep links, network errors, accessibility text scaling and low-end device performance.
- [ ] Add crash reporting and opt-in/notice as appropriate. Verify symbol upload, PII redaction and crash-free release monitoring.
- [ ] Review permissions: fine/coarse location are declared. Request location only in context, explain purpose, provide manual city choice, and verify denied/approximate/one-time permission behavior. No background location should be requested unless a separately approved feature needs it.
- [ ] Add Android notification runtime permission only when FCM push is implemented and disclosed; no current evidence of native FCM SDK/token lifecycle.

## Security and privacy engineering

- [ ] Production OTP provider and abuse/rate limiting are live; local OTP echo is impossible in production.
- [ ] JWT secrets are generated/stored in a managed secret store; refresh rotation/revocation and logout are correct; no secrets or debug tokens in the APK.
- [ ] HTTPS enforced for all production API/media hosts; reject cleartext; use secure headers on web and TLS for database/object storage connections.
- [ ] Verify secure token storage on Android (secure-storage dependency present); inspect backups, screenshots, clipboard and logs for sensitive values.
- [ ] Review dependency vulnerabilities and lockfiles; produce SBOM/signing provenance and address critical/high findings.
- [ ] Verify API authorization for customer ownership, merchant owner/member roles, admin/superadmin, SSE subscriptions, media access and all object IDs.
- [ ] Restrict MinIO/admin consoles and database ports from public access. Use cloud object storage with least-privilege private bucket policy in production.
- [ ] Add tested database backup/restore, migration forward/rollback policy, incident contacts and retention/deletion operations.
- [ ] Configure crash/analytics tools to avoid collecting phone, OTP, access token, precise location, KYC documents or message contents unless strictly necessary and disclosed.

## Privacy policy, Data safety and user rights

- [ ] Publish a public privacy policy URL in Play Console and link it in-app. Explain collection/use/sharing/retention/deletion for phone, location, business details, KYC, photos, booking/request messages, device tokens and diagnostics.
- [ ] Complete Play Data safety answers from actual SDK/network behavior. Audit all transitive SDKs and server collection; do not infer answers from feature descriptions.
- [ ] Provide consent/notice at the time location and other sensitive data are collected, explain whether location is precise/coarse, foreground/background, and offer manual location choice.
- [ ] Provide a working in-app account deletion flow and a public web deletion request path if the account can be created in-app. API currently lacks user account deletion; privacy screen text alone is not sufficient.
- [ ] Define deletion/anonymization effects for saved businesses, reviews, service requests, orders, KYC, billing invoices and legal retention. Explain exceptions and timelines.
- [ ] Define privacy contact/grievance mechanism, response SLA, data access/correction process, breach response and vendor/subprocessor list.
- [ ] Obtain Indian privacy counsel review for applicable Digital Personal Data Protection Act/rules and commencement/implementation status, consent/notice, children, data principal rights, grievance and breach obligations. Confirm applicability to merchant KYC and precise location processing.
- [ ] Obtain tax/accounting/legal review for merchant subscription/registration invoices, GST treatment, cancellation/refund and consumer-facing claims.

## Product and store-listing requirements

- [ ] Confirm target audience and age rating; no child-directed targeting unless policy and product controls are implemented.
- [ ] Prepare accurate listing title/short/full descriptions, category, support email/site, privacy URL, screenshots and feature graphics matching shipped functionality.
- [ ] Remove references to unavailable features or label them clearly (e.g., live courier GPS, payment, verified reviews, merchant registration) before release.
- [ ] Confirm all visible inventory/business listings are authentic, authorized and scoped to Cuttack/Jajpur. Seed/demo data must not appear as genuine businesses.
- [ ] Add support contact and operational dispute/abuse reporting workflow before public customer acquisition.
- [ ] Validate location permissions and map API billing/terms; if Google Maps is used, comply with attribution and usage restrictions.
- [ ] Verify app signing, target SDK, store content declarations, ads declaration (if applicable), financial features declaration (merchant billing if added), and app access instructions for reviewer accounts.
- [ ] Run internal then closed testing. Review pre-launch reports, crashes, ANRs, login access, permission flows and device compatibility; document go/no-go criteria.

## Backend/operations launch gates

- [ ] Real SMS OTP provider approved and delivery/abuse monitoring tested.
- [ ] Merchant onboarding/claim and KYC moderation are DB/API-backed; private KYC document access is audited.
- [ ] Merchant workspace uses authenticated APIs; tenant isolation tests cover owner/manager/staff and cross-business denial.
- [ ] If billing launches: gateway sandbox tests, webhook signature/idempotency, reconciliation, refund and invoice flows pass; no client-side payment success trust.
- [ ] If food/hospitality launches: order acceptance/cancel/inventory/date capacity and status workflows are tested end to end.
- [ ] Monitoring, paging/alert thresholds, security incident response, database backup restore and deployment rollback are exercised.
- [ ] CI passes Go tests, Flutter analyze/tests, web typecheck/build/E2E, migration smoke, OpenAPI-route drift, security/dependency scan. Current workflow and local Playwright dependency need repair.
- [ ] Deploy to HTTPS staging with production-like secrets and cloud object storage, then execute role-based smoke tests. Do not deploy from the current placeholder production workflow.

## India-specific considerations for professional review

- [ ] Confirm current DPDP Act and rules commencement, applicability, notice/consent, children, data principal rights, grievance and breach reporting obligations with counsel.
- [ ] Review telecom/SMS provider registration, sender/header/template and DLT requirements for OTP messages with the chosen provider and counsel.
- [ ] Review GST/invoicing and accounting treatment of registration fees, monthly/annual subscriptions, refunds and promotional discounts with a CA.
- [ ] Review UPI gateway terms, mandate/autopay consent and complaint/refund obligations before enabling recurring payments.
- [ ] Review consumer grievance/contact expectations and merchant claims (verified, sponsored, availability, pricing, ratings) to ensure UI accurately reflects evidence.
- [ ] Review KYC document types, storage purpose, access control, retention and deletion. Collect only documents required by approved business policy.

## Release decision

Current decision: **No-go for public Play release.** Blocking engineering items include production OTP, correct session revocation, merchant onboarding/claim persistence, debug release signing, placeholder Maps key, account deletion/privacy implementation, and production deployment/backup/CI hardening. Reassess after the checklist has named owners and executed evidence for each required gate.
