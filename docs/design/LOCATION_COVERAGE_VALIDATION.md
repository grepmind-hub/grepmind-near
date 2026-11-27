# Location coverage validation

Admin Service Areas & PINs supplies the coverage decision. Customer discovery keeps the 18-category directory. Registration and checkout use their server-side eligibility checks.

| Outcome | Customer location selector |
| --- | --- |
| Supported | Selects the confirmed area and keeps discovery available. |
| Unsupported | Shows the existing outside-area message and notification option. |
| Coverage unavailable | Shows Retry and keeps the current browsing location. |

The app no longer approves pilot PINs or constructs a list of locations after a failed request. The API returns an error if it cannot read coverage data. Inactive districts and localities are excluded.

Dart analysis and nine Flutter tests passed. The focused disposable PostGIS test passed for registration, Admin approval, inactive areas, and database errors during PIN and GPS checks. API package checks also passed for operations, platform commerce, platform catalog, and the API router.

The documented development APK built successfully. SHA-256 `51819E45A100EE6A2D817CEF7217AE44A36B64791ACC401530E83228CE8AA93B` matched on Customer `Pixel_8` (`emulator-5554`), Merchant `Pixel_8_Merchant_QA` (`emulator-5556`), and Rider `Pixel_8_Rider_QA` (`emulator-5558`). Rider reached onboarding and the Merchant AVD resumed a Customer session. Authenticated Merchant and Rider acceptance remains pending.

On Customer Android, PIN `110001` displayed the outside-area message and notification option. With Wi-Fi and mobile data disabled, PIN `754204` displayed Retry. After restoring both settings, Retry confirmed Kuanpal and returned to Customer Home. Screenshots are available locally in `apps/mobile/build/location-ui/emulator-5554/`. The Android check used the existing API. The backend changes were validated separately against disposable PostGIS.

## Merchant registration deployment and validation

On 26 November 2026, the approved registration-only backend update was deployed to `api.abashyaka.com` on the Windows host's WSL Docker stack. The image `abashyaka-api:merchant-coverage-20261126` was built from the running `efb2385` release with the registration handler and coverage query as the only source changes. The previous API image was retained. Compose recreated the API container and Nginx reloaded its upstream. The API container reported healthy and the public health endpoint returned HTTP 200. No migrations were applied.

On `Pixel_8_Merchant_QA` (`emulator-5556`), one submission reached the new API and showed the service-area mismatch message. The draft used an approved Kuanpal PIN, but its saved GPS pin was more than 12,900 km from the approved centre and outside the 15 km radius. A read-only database check confirmed that the attempt created no listing. The draft was left on the address step. Pending Review remains unverified and requires the actual storefront pin.
