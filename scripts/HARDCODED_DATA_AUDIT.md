# Remaining mock-data audit

This audit distinguishes user/business data from legitimate design tokens, API limits, enum values, test-only fixtures and explanatory placeholders. A source search alone does not prove every mock flow has been removed.

## Corrected in the map/UI automation slice

- Nearby queries now combine selected city, category and GPS radius on the backend. Only approved Cuttack/Jajpur listings are eligible.
- Map category filters come from the active API taxonomy, rather than seven fixed categories.
- Map queries have separate state from Explore. Late responses cannot overwrite a more recent city/category query.
- Radar pins use actual latitude/longitude offsets; generated angles, distances and default direction coordinates were removed.
- Map/list/detail rating displays no longer invent 4.8 stars or 128 reviews when values are missing.
- A selected-city center is described as a search center; GPS failures do not claim the user's current location was obtained.

## Still requiring implementation

| Area | Evidence in source | Required work |
|---|---|---|
| Professional profile | `service_pro_screen.dart`: fixed experience, completed-job counts, ratings and review snippets | Return authoritative profile/review metrics; remove sample testimonials |
| Appointment scheduling | `booking_scheduler_screen.dart`: fixed rate/scope options and simulated unavailable slot | Query persisted availability and rates; server-side capacity checks |
| Service status | `service_request_status_screen.dart`: fallback booking number, demo stage controls and indicative receipt fields | Persist all status transitions and receipt values; remove simulation controls |
| Food/table/hotel checkout | `business_detail_screen.dart`: local voucher/order confirmation and local totals | Persist orders/reservations and compute totals on the backend before confirmation |
| Delivery tracking | `order_tracking_screen.dart`: simulated route/progress, sample address/rider defaults | Integrate a real delivery state/location source or show unavailable tracking |
| Merchant hours/coverage | `app_provider.dart`: draft seven-day hours and fallback locality; web `HoursCoverageManager.tsx`: sample localities | Distinguish unsaved drafts from operating hours; load real service localities |
| Registration and claim | `merchant_registration_screen.dart`: static classification/category choices and photo/GPS demonstration state | Connect taxonomy, verified location, upload and claim APIs; submission currently unavailable |
| Admin/merchant desktop | Empty former sample datasets; several views/actions still use local state | Complete authenticated API wiring before claiming production-ready management |

The local OTP stub remains intentionally development-only; it is not production SMS delivery. Google map tile rendering also requires an approved Maps API key. The fixture injector is test-only and never adds permanent inventory.
