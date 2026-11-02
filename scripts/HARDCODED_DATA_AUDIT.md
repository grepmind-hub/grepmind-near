# Remaining mock-data audit

This audit distinguishes user/business data from legitimate design tokens, API limits, enum values, test-only fixtures and explanatory placeholders. A source search alone does not prove every mock flow has been removed.

## Corrected in the map/UI automation slice

- Nearby queries now combine selected city, category and GPS radius on the backend. Only approved Cuttack/Jajpur listings are eligible.
- Map category filters come from the active API taxonomy, rather than seven fixed categories.
- Map queries have separate state from Explore. Late responses cannot overwrite a more recent city/category query.
- Radar pins use actual latitude/longitude offsets; generated angles, distances and default direction coordinates were removed.
- Map/list/detail rating displays no longer invent 4.8 stars or 128 reviews when values are missing.
- A selected-city center is described as a search center; GPS failures do not claim the user's current location was obtained.

## Corrected in the operational-booking slice

- Professional metrics, services, availability, operating hours and coverage use persisted API data.
- Food, table and hotel orders are persisted and priced by the backend before confirmation.
- Service and order stages can no longer be advanced locally by customers.
- Missing courier GPS, payment, support and review data render explicit unavailable states.
- Empty merchant schedules/localities remain empty until the merchant deliberately creates a draft.

## Still requiring implementation

| Area | Evidence in source | Required work |
|---|---|---|
| Registration and claim | `merchant_registration_screen.dart`: static classification/category choices and photo/GPS demonstration state | Connect taxonomy, verified location, upload and claim APIs; submission currently unavailable |
| Admin/merchant desktop | Empty former sample datasets; several views/actions still use local state | Complete authenticated API wiring before claiming production-ready management |

The local OTP stub remains intentionally development-only; it is not production SMS delivery. Google map tile rendering also requires an approved Maps API key. The fixture injector is test-only and never adds permanent inventory.
