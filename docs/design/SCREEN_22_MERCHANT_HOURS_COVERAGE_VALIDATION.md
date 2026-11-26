# Screen 22 Merchant Hours & Coverage Setup

On 26 November 2026, the active Merchant session on `Pixel_8_Merchant_QA` (`emulator-5556`) opened Hours & Coverage from the Merchant Workspace. The weekly schedule loaded and an opening-time picker opened. The Service Coverage tab loaded a 5 km radius. Selecting the 10 km preset updated the displayed radius, then the preset was returned to 5 km without saving.

The emulator session displayed GrepMind Enterprise. Live persistence for the intended merchant remains pending. No operating hours or coverage settings were saved during this check.

All four tests in `test/merchant_hours_coverage_test.dart` passed via Flutter in WSL. They cover schedule rendering, closed-day controls, the Appointments retry state, and coverage controls.
