# AGENTS.md — Grepmind Near

## Project identity

Grepmind Near is a local business and service discovery platform under the Grepmind brand. Everything nearby. One tap away.

## Reference UI kit

Screen-by-screen reference images live in `ref-image/`:
- Onboarding and location
- Explore home
- Search and results
- Nearby map
- Business profile
- Service request
- Saved businesses
- Merchant workspace
- Admin web portal
- Color palette
- Reusable components
- Sample UI design

These images define the premium 2026 visual direction: light-first interface, deep blue (#2457D6) primary, teal (#0F766E) discovery, Inter typography, consistent outline icons, real local business photography, minimal elevation, 16px card radius, 4px base spacing.

## Technology

- Android application: Flutter and Dart (Riverpod state, GoRouter navigation, Dio networking)
- Backend: Go REST API (chi router, pgx/sqlx, PostgreSQL + PostGIS)
- Merchant and admin portals: Next.js and TypeScript
- API contract: OpenAPI (`api/openapi.yaml`)
- Local development: Docker Compose

## Architectural rules

1. Modular monolith for the initial backend.
2. Flutter code organized by feature; presentation separate from networking and persistence.
3. Treat OpenAPI as the authoritative HTTP contract.
4. Parameterized SQL and database constraints.
5. Business rules in application services, not HTTP handlers.
6. Minimal dependencies; explain material additions.
7. No microservices, Redis, Kafka, Kubernetes, or vector DBs without approved requirement.
8. No manual API schema duplication when generation is practical.
9. Versioned, reviewable database migrations.
10. Preserve existing behaviour unless explicitly authorized.

## Security rules

1. Enforce authorization and ownership on the backend.
2. Never trust client-supplied roles, verification status, price totals, or booking status.
3. Never commit secrets or log OTPs, access tokens, or sensitive location data.
4. Validate input and enforce bounded query parameters.
5. Use transactions for atomic operations.
6. Tests for unauthorized access and invalid state transitions.
7. Keep customer location data to the minimum required.

## UI rules

1. Follow documented design tokens and screen specifications.
2. Reuse existing design-system components.
3. Loading, empty, error and success states on every API-driven screen.
4. Accessible text scaling and screen readers.
5. Usable touch targets on Android (min 48 dp).
6. Never fabricate availability, verification, inventory, ratings or offers.
7. Clearly label sponsored content.
8. Responsive and performant on lower-end devices.

## Workflow

1. Inspect relevant code and documentation before editing.
2. Summarize planned changes for nontrivial tasks.
3. Smallest complete change satisfying the task.
4. Add or update tests.
5. Run formatters, static checks and tests.
6. Review diff for security, compatibility and unintended changes.
7. Report modified files, test results, assumptions and outstanding risks.

## Prohibited without explicit approval

- Deploying to production.
- Destructive production database commands.
- Rotating or exposing credentials.
- Rewriting shared API contracts or database history without migration plan.
- Adding substantial new infrastructure.
- Removing tests or weakening security controls to obtain a passing build.

## Completion standard

Do not claim success unless checks were actually executed. If a check cannot run, report it clearly.

## Implementation task template

Implement the following task for Grepmind Near:

TASK:
[One narrowly scoped feature or engineering task]

AUTHORITATIVE DOCUMENTS:
- AGENTS.md
- Relevant product specification
- Relevant screen specification
- api/openapi.yaml
- Relevant architecture and database documents

CONSTRAINTS:
- Preserve existing architecture.
- Do not implement unrelated features.
- Do not add dependencies without explaining why.
- Do not change public API contracts without approval.
- Use parameterized SQL and enforce authorization.
- Include appropriate tests and error handling.

PROCESS:
1. Inspect existing implementation and relevant documents.
2. Identify dependencies, assumptions and affected files.
3. Implement smallest complete vertical slice.
4. Add or update automated tests.
5. Run formatters, static analysis and tests.
6. Review diff for regressions and security issues.
7. Update documentation if behaviour changes.

FINAL REPORT:
- Summary of changes.
- Files created or modified.
- Tests actually executed and their results.
- Decisions or assumptions made.
- Known limitations and remaining risks.
- Recommended next task.
