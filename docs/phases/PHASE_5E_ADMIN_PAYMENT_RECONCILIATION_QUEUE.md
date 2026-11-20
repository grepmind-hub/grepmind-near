# Phase 5E — Admin Payment Reconciliation Queue

**Status — PASS for isolated Admin Web read-only acceptance (16 November 2026).**

Admin Web lists current attempts with status `reconciliation_required` ahead of recorded reconciliation exceptions. An attempt can appear in both groups when its exception is still outstanding. An exception remains visible as history if its attempt later succeeds. Matched reconciliation events stay out of the queue. Rows link by order UUID to Payment Tracking and load that order automatically.

`GET /api/v1/admin/payments/reconciliation-queue` requires `finance.read`, responds with up to 50 rows and a truncation indicator, and uses a read-only PostgreSQL transaction. It exposes current attempt state, amount, currency, and the recorded outcome. This slice requires no migration and adds no reconciliation action.

## Acceptance

The disposable QA database ran migrations 001–041. The protected OTP reader authenticated the synthetic actors, and independent Admins approved the browser account for `finance.read`. Authorized application endpoints created sandbox payment sessions. Verified sandbox webhooks with amounts that differed from the immutable attempts produced real reconciliation events.

| Order | Current attempt status | Recorded outcome | Queue result |
| --- | --- | --- | --- |
| `GN-45CFF751` | Reconciliation required | Amount mismatch | First action-required row and a separate exception row |
| `GN-97D0A843` | Succeeded | Amount mismatch | Historical exception only |
| `GN-DDCAAAFC` | Succeeded | Matched | Excluded |

The live Playwright test authenticated through the Admin UI, matched queue rows and attempt IDs to PostgreSQL, and followed the action-required order link to its Payment Tracking view. The empty case was checked through the live API when only a matched event existed. HTTP 401 covered unauthenticated access. HTTP 403 covered both Customer and Admin accounts lacking `finance.read`. The two sandbox capture journals balanced. Live financial flags remained disabled.

The Admin production build, API image build, Go payments and API tests, Go vet, targeted ESLint, and OpenAPI parsing passed. Admin Web was the acceptance surface. The synthetic underlying checkout and payment events ran through isolated APIs.

[Queue screenshot](evidence/phase5e/reconciliation-queue.png).

## Existing isolated QA deployment

A fresh Admin production build and the reconciliation queue API image were deployed to the existing isolated QA portal on port 18302. Post-deploy checks confirmed the dashboard contains the queue, the Payment Tracking deep link responds, the queue rejects unauthenticated requests, and PIN sign-in remains enabled. The prior API container is retained stopped for rollback. Deployment reused the existing isolated database schema and finance settings.
