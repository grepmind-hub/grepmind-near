# Merchant application review

Open **Listing Verification → View details** or **Merchant Registry → View details** to review the application. The drawer shows the business, owner and contact information, locality, PIN, coordinates, operating schedule, and submitted storefront photo. Enter the evidence reference to verify and approve, or enter a rejection reason.

**Print / Save PDF** opens the browser print dialog with the application reference, details and storefront photo on a print layout. Select an A4 printer or Save as PDF. Dashboard navigation and decision controls are excluded from print.

The review API and photo endpoint require an Admin account and return private, non-cacheable responses. The image streams from the existing media store. The storefront photo remains optional. New Android submissions save the owner name, email, registration ID or No GST selection, enterprise type, operating mode and requested radius with the listing transaction. Older submissions show the fields already stored on the listing and owner account. Fields never sent by older clients cannot be recovered.

For release, apply migration 049 with the approved database migrator, deploy the API and Admin web, then distribute the Android build that sends the additional fields. Verify a legacy application and a new authorized test application after release.

Local verification covered the Admin production build, browser review and A4 PDF generation with a fixture photo, Admin-only reads and legacy registration on disposable PostGIS, and five Flutter merchant registration tests. The shared database and live Admin portal were not updated.
