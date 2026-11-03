# Merchant Billing Specification

Status: planning only; no billing code or database schema was added by this audit. Amounts, tax treatment, plan prices and legal invoice wording require business/accounting approval.

## Business rules

### Customers

- Customer registration, OTP login, search, discovery, saved listings, inquiries and customer-facing use remain free.
- Do not collect customer marketplace checkout money in this billing module. Food delivery payments, if later introduced, are a separate product/payment scope.

### Merchants

- One-time listing registration fee is a distinct payment from recurring subscription.
- Merchant selects monthly or annual subscription after onboarding/KYC policy is defined.
- Subscription activates only after server-verified payment success; client redirect or submitted UPI reference is never sufficient.
- Renewal reminders are sent before expiry; failed/expired subscription state is explicit. Define read-only/grace/visibility behavior before gating merchant capabilities.
- A payment covers a merchant account or one business? Recommended MVP: one billing account per legal merchant owner, with an explicit included-business count. Avoid silently charging each branch until pricing is approved.
- Subscription price, tax/GST, grace days, refund rules and registration fee refundability are configuration/business decisions, not assumptions in code.

## India-compatible payment recommendation

Use a payment gateway that provides a hosted checkout/UPI intent or QR flow, server-side order creation, signed webhooks, refunds and settlement reports. Razorpay is a practical first candidate for India due to common UPI and subscription/payment-link support; evaluate current merchant onboarding, subscription UPI AutoPay support, pricing, settlement, refund and webhook behavior against current official provider documentation before selecting. Cashfree Payments or PhonePe PG are alternatives. Do not implement direct UPI collect scraping or trust screenshots/UTRs as proof.

MVP recommendation: gateway-hosted one-time checkout for registration and each subscription renewal, with merchant manually initiating renewals. Add recurring UPI AutoPay only after provider support/mandate lifecycle, user consent and failure handling are validated. It keeps recurring mandates out of the first launch while preserving automated webhook reconciliation.

## Architecture

Keep this inside the existing Go modular monolith, PostgreSQL and merchant portal. Suggested packages: `backend/internal/billing` for plan/catalog, checkout, webhook verification, subscription state and invoices. Gateway adapter interface isolates provider specifics without a microservice.

Flow:

1. Authenticated owner requests a checkout for an approved billable business.
2. API reads the server-defined registration fee or plan price and creates a pending local payment row with an idempotency key.
3. API creates the provider order using a server-only credential and returns a hosted checkout URL/order ID. Never accept amount/currency from browser.
4. Gateway sends webhook. API validates signature against exact raw request bytes, checks provider event/order/payment IDs, amount, currency and merchant metadata, and deduplicates event ID.
5. In one DB transaction, record verified payment, activate/extend subscription once, create immutable invoice snapshot and billing audit entry.
6. Browser return page polls authenticated local payment status. Return URL alone never activates service.
7. Worker schedules renewal reminders and expires subscriptions using persisted timezone/plan rules; retries are idempotent.

## Proposed database design

Add a new, reviewed migration only after this specification is approved. Do not edit earlier migrations.

### `billing_plans`

- `id`, `code` (unique), `name`, `interval` (`monthly`, `annual`, `one_time`), `amount_minor` integer, `currency` (`INR`), `tax_code`/tax metadata if approved, `included_businesses`, `features` JSONB, `is_active`, effective dates, created/updated timestamps.
- Plan price changes create new version/code or effective-dated rows; do not overwrite historical invoice amounts.

### `merchant_billing_accounts`

- `id`, `owner_user_id`, optional legal/business details, billing email/phone, GSTIN only if required, `status`, `created_at`, `updated_at`.
- Unique/account ownership rules should be defined for sole proprietor, company and multi-owner cases.

### `merchant_subscriptions`

- `id`, `billing_account_id`, `plan_id`, `status` (`pending`, `active`, `past_due`, `grace`, `cancelled`, `expired`), `current_period_start`, `current_period_end`, `cancel_at_period_end`, `activated_at`, `ended_at`, provider customer/subscription refs, created/updated.
- Enforce at most one current active subscription per account where product rules require it; preserve subscription history.

### `billing_payments`

- `id`, `billing_account_id`, optional `business_id`, optional `subscription_id`, `purpose` (`registration_fee`, `subscription`), `provider`, `provider_order_id`, `provider_payment_id`, `amount_minor`, `currency`, `status` (`created`, `pending`, `succeeded`, `failed`, `refunded`, `partially_refunded`), idempotency key, failure code (safe), paid/refunded timestamps, created/updated.
- Unique provider order/payment IDs and account+idempotency key. Store no card/bank/UPI PIN credentials.

### `billing_webhook_events`

- `provider`, `provider_event_id` unique, event type, received timestamp, signature-valid boolean, processing status, safe metadata/hash, processed timestamp/error code. Avoid persisting unnecessary raw personal payloads.

### `billing_invoices` and `billing_invoice_lines`

- Immutable invoice number unique per legal entity/financial-year policy, billing account, related payment/subscription, issued date, currency, subtotal, tax components, total, seller identity/GSTIN if applicable, buyer snapshot, status/credit-note linkage.
- Line rows snapshot item description, quantity, unit amount, tax rate and tax amount. Corrections issue credit notes/new invoices; never mutate paid invoice totals.
- Exact numbering, GST and invoice language requires accountant/legal review.

### `billing_audit_events`

- Actor/system, account, object type/id, event, safe reason/details, created time; append-only application permissions.

## API requirements

All routes are under `/api/v1`, use bearer auth in the existing pattern, and enforce business owner/member rules by `business_id`. Do not accept client role or prices.

- `GET /merchant/billing/plans` — active plans and price/version details.
- `GET /merchant/billing/account` — current billing profile, account, business entitlement summary.
- `PUT /merchant/billing/account` — validated billing details, role/ownership scoped.
- `POST /merchant/billing/registration-checkout` — create pending fee payment for eligible business; idempotent.
- `POST /merchant/billing/subscription-checkout` — server-selected plan checkout/renewal; idempotent.
- `GET /merchant/billing/payments` — cursor-paginated history for account, not other merchants.
- `GET /merchant/billing/invoices/{id}` — scoped invoice metadata and authorized download URL.
- `POST /billing/webhooks/{provider}` — no browser bearer requirement; raw body size cap, signature validation, event deduplication, replay-safe transactional processing, generic responses.
- `GET /merchant/billing/payments/{id}` — poll server payment status after checkout return.
- Admin: `GET /admin/billing/accounts`, `GET /admin/billing/payments`, `GET /admin/billing/subscriptions`, and audited actions for manually granting/revoking entitlement with reason + second-person controls if business policy requires it. No manual “mark paid” action without immutable audit and reconciliation source.

Document paths/schemas in OpenAPI; add route authorization and webhook signature/idempotency tests.

## Merchant portal changes

- Billing overview: current plan, status, billing period, included businesses, next renewal date, action required.
- Registration payment step: fee and tax disclosure before redirect; explain payment verification delay and retry behavior.
- Plan comparison: monthly/annual terms and renewal conditions; no preselected paid plan or misleading default.
- Payment history: date, purpose, amount, currency, status, provider reference, invoice download.
- Renewal reminders: in-app/email/SMS channel chosen after contact consent/config; notification state and deep link to payment.
- Grace/expired state: exact capability policy disclosed and consistent with customer listing availability.
- Keep secrets and signature verification entirely on backend. Browser only receives checkout reference/URL.

## Admin controls

- Plan CRUD/versioning with effective dates and audit log.
- Billing account/subscription/payment search scoped to Cuttack/Jajpur operating data.
- Webhook processing health, unmatched events and safe retry of idempotent failures.
- Invoice/payment reconciliation and refunds through provider, with reason and audited actor.
- Manual entitlement exception only with reason, expiry and audit event; never edit payment as paid.
- Reporting: gross collections by registration/subscription, refunds, failures, renewals and outstanding accounts; distinguish provider settlement from captured payments.

## Payment and renewal rules

- Server amount in integer paise; currency fixed to INR unless product expands.
- Verify signature, provider order ID, local amount, currency, merchant/account reference and event status.
- Deduplicate webhook events and provider payment IDs. Handle out-of-order/duplicate events and delayed success after browser timeout.
- One-time registration fee success must not accidentally create subscription entitlement unless product policy explicitly bundles it.
- Subscription period uses plan and server payment timestamp; define annual calendar rules and timezone.
- Failed renewal: notify, retry according to provider/plan policy, apply documented grace, then expire. Never silently renew or charge without valid user consent/mandate.
- Refunds/cancellations create new ledger events and provider references; preserve invoice/credit note history.
- Reconcile daily provider reports against local captured/refunded ledger before financial reporting is trusted.

## Security, privacy and tax review

- Store credentials in deployment secret manager. Verify provider webhook secret rotation and timing-safe signature comparison.
- Do not store UPI PIN, full bank credentials, card PAN/CVV or OTP. Minimize provider payload retention and redact logs.
- Use idempotency keys on browser initiation and webhook consumption; rate limit checkout initiation.
- Require HTTPS; restrict webhook size/content type; protect admin billing routes with stronger admin session/MFA policy if available.
- Obtain Indian CA/accountant and legal review for GST registration/tax inclusion, invoice numbering, refunds, auto-renewal consent, Consumer Protection obligations, data-protection notices, grievance contact and records retention.
