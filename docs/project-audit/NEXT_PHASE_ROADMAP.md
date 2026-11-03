# Next Phase Roadmap

Audit date: 3 November 2026. Estimates are solo-developer effort ranges for implementation plus focused tests; they exclude provider onboarding/approval delays and external legal/accounting decisions.

## Ranked top 10

| Rank | Feature | Current status | Value | Dependencies | Security implications | Complexity | Priority/reason |
|---:|---|---|---|---|---|---|---|
| 1 | Production auth, OTP abuse controls, token lifecycle | PARTIALLY IMPLEMENTED | Enables real accounts and reduces account takeover/OTP abuse | Select SMS provider, production secrets, account/session policy | Very high: OTP brute force, SIM swap, refresh replay, PII | L (2–3 weeks) | P0. Every real customer, merchant, billing and support flow depends on it. |
| 2 | Merchant onboarding/claim + KYC persistence | UI ONLY / MOCKED | Converts merchant interest to usable supply and approved listings | Auth, city/category API, private media upload, moderation rules | Very high: ownership fraud, KYC PII/document access | L (2–4 weeks) | P0. Current merchant product cannot acquire/manage trustworthy businesses end to end. |
| 3 | Merchant billing: registration fee + plans + UPI gateway | NOT IMPLEMENTED | Monetization and predictable recurring revenue | Approved pricing/tax/refund policy; onboarding/account model; provider contract | Very high: webhook fraud, amount tampering, payment PII, entitlement errors | XL (4–6 weeks) | P0 after auth/onboarding contract. Must precede paid launch. |
| 4 | Replace merchant-web fixture state with API-backed tenant workspace | UI ONLY / MOCKED | Keeps operations and tenant isolation consistent across desktop/mobile | Auth/onboarding, consistent `/merchant/businesses` APIs | Very high: cross-tenant IDOR and XSS/token theft | L (2–3 weeks) | P0. Existing UI is misleading and not durable. |
| 5 | Migration system, backup/restore, staging and CI repair | PARTIALLY IMPLEMENTED | Prevents deploy drift/data loss and catches regressions | Choose migration tool/ledger, CI secrets/test data | High: destructive migration, leaked CI credentials | M (1–2 weeks) | P0. Needed before any schema/payment rollout. |
| 6 | Reviews and rating integrity | NOT IMPLEMENTED | Trust and discovery conversion | Completed job/order model, moderation/report flow, identity | High: fake reviews, harassment, personal data | M (2–3 weeks) | P1. Important after the first stable transaction/request cycle. |
| 7 | Booking/reservation operational lifecycles | PARTIALLY IMPLEMENTED | Makes service, table, hotel and food requests dependable | Slot management UI, overlap/capacity rules, merchant acceptance, cancellation policy | High: overbooking, unsafe contact/location exposure | L (2–4 weeks) | P1. Current order rows are persistent, but slots/inventory/merchant lifecycle gaps remain. |
| 8 | Native Android FCM notifications | NOT IMPLEMENTED | Re-engagement and timely service status | FCM credentials, consent/preferences, device token lifecycle | High: token exposure, notification privacy leakage | M (1–2 weeks) | P1. SSE serves active browser sessions only; background mobile users need push. |
| 9 | Search/location accuracy and performance | PARTIALLY IMPLEMENTED | Core local relevance and lower latency | Geocoding/map provider selection, city boundary policy, privacy review | High: precise location handling/API key limits | M (1–2 weeks) | P1. Validate the two-city product with real devices and coverage data. |
| 10 | Customer support, dispute handling, production observability | PARTIALLY IMPLEMENTED | Resolution and operational confidence | Support owner/process, privacy policy, log/alert provider | High: sensitive messages, audit integrity | M (2–3 weeks) | P1. Required for public operations; some admin report endpoints exist, user support channels do not. |

Google Play production readiness is a release gate across all ranks, not a standalone feature sprint. Signing, package identity, privacy/account deletion, Data safety, store listing and release monitoring must be complete before rollout.

## Recommended next three phases

### Phase 1 — Production foundations and merchant onboarding (about 4–6 weeks)

1. Fix auth/session lifecycle and add rate limiting; configure real SMS OTP in staging.
2. Add route/tenant authorization tests and migration runner/restore procedure.
3. Implement merchant create/claim, private KYC media and admin review end to end.
4. Make merchant workspace API-backed and enforce owner/member role rules.

Dependency order: merchant billing cannot safely bind payments/entitlements until identity, billing-account ownership and active business state are authoritative.

### Phase 2 — Merchant UPI billing (about 4–6 weeks after decisions)

1. Approve fee, monthly/annual prices, tax display, refund/grace/cancellation rules.
2. Select gateway and complete merchant account activation/test environment.
3. Add plans, billing accounts, payments, webhook events, subscriptions, invoices and audit tables in a new migration.
4. Implement server-created checkout, signed webhook verification, idempotent activation, history/invoices, renewal jobs/reminders and admin monitoring.
5. Verify payment success/failure/duplicate/delayed webhook/refund paths in provider sandbox.

### Phase 3 — Trust and operational completion (about 4–7 weeks)

1. Add merchant availability management and concurrency/overbooking tests.
2. Decide operational launch scope; complete food/table/hotel status, cancellation and inventory rules or hide unsupported actions.
3. Add verified review flow and moderation.
4. Add FCM, customer support/dispute intake, analytics and observability.
5. Run release candidate on representative low-end Android devices and closed Play testing.

## Solo-developer execution plan

- Work in 1–3 day slices; finish one API-to-screen flow, tests, docs and review before starting another.
- Cap the active work-in-progress at one feature plus one blocker. Keep billing provider/legal decisions in a short decision log.
- Reserve roughly one day per week for regression, dependency updates, backups and release hygiene; do not defer all QA to launch.
- Use generated test identities and disposable local/test data. Never use production records for injection tests.
- Keep core first public launch narrow: free customer discovery plus real merchant listings/contacts/inquiries, if paid billing or complex hospitality paths are not ready. Avoid exposing UI for workflows that imply confirmed availability, payment or courier tracking when those systems do not exist.

## Evaluation of requested areas

- **Production security/reliability:** first; foundational and launch blocking.
- **UPI registration payment:** high business value, after account and merchant onboarding rules.
- **Subscription management:** implement with first billing module, but begin with manual renewal payment and server-verified activation; postpone auto-debit mandates.
- **Verified reviews:** high trust value, after completed service/order verification exists.
- **Merchant onboarding/verification:** immediate supply-side blocker, before payment entitlement enforcement.
- **Native FCM:** useful after state transitions and notification preferences are stable.
- **Search/location accuracy:** validate current two-city filters/permission UX; avoid investing in larger city expansion before precision/privacy checks.
- **Support/disputes:** create minimum contact and ticket intake before public launch; expand admin workflows after merchant operations stabilize.
- **Performance/observability:** add request IDs, health metrics, crash monitoring and query checks before increasing acquisition.
- **Google Play readiness:** cross-cutting final gate, begin privacy, signing and package identity work early because approvals and policy review can take time.
