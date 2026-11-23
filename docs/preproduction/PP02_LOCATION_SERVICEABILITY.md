# Phase PP-02: Location, GPS & PIN Code Serviceability Specification

## 1. Objective & Architectural Overview

To deliver an accurate, fast, and server-authoritative serviceability experience that prevents ordering from unsupported locations while enabling discovery where partners are active.

```
+-----------------------------------------------------------------------------------+
| Customer Opens App -> Contextual Location Check                                   |
+-----------------------------------------------------------------------------------+
         |                                                 |
         v                                                 v
[ Use GPS Location ]                             [ Enter Location Manually ]
  - Foreground permission request                  - 6-digit Indian PIN code search
  - High-accuracy coordinate fix                   - Locality / Landmark search
  - Reverse geocode to Locality                    - Recent / Saved address picker
         |                                                 |
         +------------------------+------------------------+
                                  |
                                  v
         [ Server-Side Authoritative Serviceability Check ]
              API: POST /api/v1/serviceability/check
              Backend: Go REST + PostgreSQL + PostGIS
              Validates: PIN Code + Coordinates + Capability Flags
                                  |
        +-------------------------+-------------------------+
        |                                                   |
        v                                                   v
[ Service Available ]                             [ Outside Service Area ]
  - Filter category capabilities                    - Dedicated 2027 Empty State
  - Display available merchants                     - Display selected locality & PIN
  - Enable cart & ordering                          - "Notify me when available"
                                                    - "Change location"
```

---

## 2. Admin-Controlled Coverage Matrix

Coverage is controlled dynamically from the Admin Portal without rebuilding the mobile application:

| Hierarchy Level | Example | Operational Attributes |
|---|---|---|
| **State** | Odisha | Regional platform governance. |
| **District** | Cuttack / Khordha / Puri | Administrative boundary. |
| **City / Town** | Cuttack / Bhubaneswar / Jajpur | Primary hub. |
| **Locality / Village** | Chhatia / Kuanpal / Infovalley | Service polygon / radius. |
| **PIN Code** | 754023, 751024, 755001 | 6-digit postal zone verification. |
| **Coordinates** | Latitude, Longitude | Precise PostGIS `ST_DWithin` calculations. |
| **Service Radius** | 5.0 km – 15.0 km | Delivery and rider dispatch bounding circle. |

### Capability Flags (Per Location):
- `food_delivery_enabled`: Boolean
- `grocery_delivery_enabled`: Boolean
- `medicines_delivery_enabled`: Boolean
- `local_services_enabled`: Boolean
- `transport_enabled`: Boolean
- `merchant_discovery_enabled`: Boolean

*Partial Availability Rule:* If a location supports `merchant_discovery_enabled` but not `food_delivery_enabled`, the user can browse local businesses, but food checkout displays a clear capability advisory rather than a hard application block.

---

## 3. GPS & Permission Handling Rules

1. **Contextual Permission Primer:** Display an informative dialog before invoking the Android system location dialog explaining *why* location is needed ("Find nearby stores, accurate delivery estimates, and local service providers").
2. **Permission Outcomes:**
   - **Precise / Approximate Granted:** Obtain location via `Geolocator.getCurrentPosition()` with a 6-second timeout.
   - **Denied:** Gracefully open the manual PIN / locality picker bottom sheet.
   - **Permanently Denied:** Show a friendly helper button directing to "App Settings".
   - **GPS Disabled:** Prompt customer to turn on device location services with one tap.
3. **No Background Location:** Customer mode *never* requests background location permissions.

---

## 4. "Outside Service Area" Premium Experience

When a customer's selected GPS or PIN code is not currently serviced:
- **Visual:** Clean 3D store illustration with map pin.
- **Badge:** `Expanding our coverage` (Amber pill).
- **Title:** `We're not in your area just yet.`
- **Body:** `Abashyaka is growing neighbourhood by neighbourhood. We're working to bring trusted local shops and convenient services closer to you.`
- **Location Summary Card:** Displays the detected PIN code and locality name.
- **Actions:**
  1. **Primary Button:** `Notify me when available` (Registers customer interest in backend `location_interest_leads` table).
  2. **Secondary Button:** `Change location` (Opens the locality selection sheet).

---

## 5. Acceptance Verification Gate

- Supported PIN code loads serviceable merchants and active categories.
- Unsupported PIN code renders the "Outside Service Area" recovery view with "Notify Me" action.
- GPS denied / timeout smoothly falls back to manual PIN entry without blank screen or crash.
- Admin coverage changes take effect dynamically on the next API refresh.
