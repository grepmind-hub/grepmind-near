# Screen 17: Customer Profile & Settings — Implementation & Design Guide

> **Authoritative Blueprint for Incoming Coding Agents (Codex / AGY)**  
> **Screen Name:** Customer Profile & Settings (Screen 17 of the 22-Screen UI Showcase)  
> **Source Location:** `apps/mobile/lib/core/screens/profile_screen.dart`  
> **Associated Tests:** `apps/mobile/test/profile_screen_test.dart` (7 tests, all passing)  
> **Design Language:** Metallic Teal Abstract Fluid Wave + Pearl White Glossy UI  
> **Primary Tokens:** Premium Obsidian (`#101820`) & Graphite Charcoal (`#374151`)

---

## 1. Context & Purpose for the Incoming Agent

This guide serves as a drop-in technical specification for implementing and verifying **Screen 17 (Customer Profile & Settings)** in the Abashyaka mobile application. 

Previous phases completed and verified:
- **Screen 10 (Nearby Interactive Map)**: Interactive radar beam, 18 category nature badges, synchronized list/radar filters.
- **Screen 11 (Business Profile & Tabs)**: Role selection wave backdrop, context-aware action buttons (`Call Driver` / `Book Ride`, `Call Clinic` / `Book Appointment`, `Call Restaurant` / `View Menu`), interactive user review submission modal, verified reviews increment.
- **Screen 16 (Saved / Bookmarked Businesses)**: Pearl white fluid-wave header, category nature badge chips, context-aware CTAs, and offline curated recommendations fallback.

Now, **Screen 17 (`profile_screen.dart`)** must be aligned with the same **2026 Metallic Teal + Pearl White Glossy + Premium Obsidian** design system while preserving 100% of the existing auth providers, secure storage, and test contracts.

---

## 2. Approved 2026 Design Tokens & Color Palette

All styling must be derived from `AbashyakaColors` (`apps/mobile/lib/core/theme/app_theme.dart`). Do **not** use legacy hardcoded green (`0xFF059669`) or legacy text colors (`#102B32`, `#4A626A`).

### Typography Tokens
| Token | Hex Value | Flutter Style | Role in Screen 17 |
|---|---|---|---|
| **Premium Obsidian** | `#101820` | `AbashyakaColors.premiumObsidian` | Screen title, card section titles, user full name, tile main labels. |
| **Graphite Charcoal** | `#374151` | `AbashyakaColors.graphiteCharcoal` | Subtitles, account ID, secondary descriptions, metadata labels. |
| **Muted Hint** | `#9CA3AF` | `AbashyakaColors.subtleBorder` | Form borders, placeholder texts, disabled icons. |

### Brand & Functional Colors
| Token | Hex Value | Role in Screen 17 |
|---|---|---|
| **Signature Teal** | `#00545B` / `#0F766E` | Primary action buttons, edit button, wave gradients, avatar halo. |
| **Metallic Teal** | `#007D80` | Active icon highlights, focus borders, verified checks. |
| **Luminous Aqua** | `#00B3AE` | Wave crest highlights, verified badge borders. |
| **Pearl White (Canvas)** | `#F5FAFA` / `#F8FAF9` | Scaffold background canvas. |
| **Pure Glossy White** | `#FFFFFF` | Profile cards, modal sheets, elevated action surfaces. |
| **Success Emerald** | `#16A34A` | "Verified" check chips, active account status indicator. |
| **Coral Accent** | `#E11D48` | Saved places bookmark icon, logout button highlight. |

---

## 3. Screen Structure & Architectural Layout

`profile_screen.dart` is structured into 4 primary visual tiers:

```
+-------------------------------------------------------------------------+
| [<-]  My Profile                                                    [Edit]|
+-------------------------------------------------------------------------+
| [Fluid Wave Header Backdrop (role_selection_background.webp)]          |
|                                                                         |
|  +-------------------------------------------------------------------+  |
|  | (Avatar + Camera)    A Grepmind Customer                          |  |
|  |  [Key: photo_btn]    +919876543210 [✔ Verified]                  |  |
|  |                      [CUSTOMER]                                   |  |
|  +-------------------------------------------------------------------+  |
+-------------------------------------------------------------------------+
|                                                                         |
| +---------------------------------------------------------------------+ |
| | CARD 1: Personal Details                                    [Edit]  | |
| | - Full Name: A Grepmind Customer                                    | |
| | - Mobile Phone: +919876543210 [✔ Verified]                          | |
| | - Email Address: user@grepmind.com                                  | |
| | - Primary Address: Main Chowk, Chhatia, Cuttack                      | |
| | - Language: English                                                 | |
| | - Account ID: 12345678...9012 [Key: short_account_id] [Copy]        | |
| | - Account Status: Active                                            | |
| +---------------------------------------------------------------------+ |
|                                                                         |
| +---------------------------------------------------------------------+ |
| | CARD 2: Account & Portals                                           | |
| | - My Orders & Bookings               -> OrderHistoryScreen          | |
| | - Saved businesses [Key: saved_biz]  -> SavedScreen                 | |
| | - Saved addresses                    -> CustomerAddressesScreen     | |
| | - Become a delivery partner          -> RiderApplicationScreen      | |
| | - Register / Claim Business          -> MerchantRegistrationScreen  | |
| | - Switch Portal / Experience         -> RoleSelectionScreen         | |
| +---------------------------------------------------------------------+ |
|                                                                         |
| +---------------------------------------------------------------------+ |
| | CARD 3: Security & Preferences                                      | |
| | - Sign-in & Security (OTP Phone Auth — No password fields!)         | |
| | - Notification Settings (Push delivery status check)                | |
| | - App Version & Build info                                          | |
| +---------------------------------------------------------------------+ |
|                                                                         |
| [ Log Out Button (Outlined with Red Accent) ]                           |
+-------------------------------------------------------------------------+
```

---

## 4. Reusable UI Components & Implementation Rules

### 1. Card Container (`PremiumCard` or Styled Container)
Use consistent card styling:
```dart
Container(
  decoration: BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(20),
    border: Border.all(color: const Color(0xFFE2E8F0), width: 1),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.04),
        blurRadius: 12,
        offset: const Offset(0, 4),
      ),
    ],
  ),
  padding: const EdgeInsets.all(18),
  child: ...
)
```

### 2. Mandatory Test Keys (DO NOT REMOVE OR RENAME)
The test suite in `apps/mobile/test/profile_screen_test.dart` asserts the presence of these exact keys:
1. `const ValueKey('short_account_id')`: Must be attached to the widget displaying the truncated/compact user ID.
2. `const ValueKey('profile_photo_button')`: Must be attached to the camera/photo button on the user avatar.
3. `const ValueKey('profile_saved_businesses')`: Attached to the "Saved businesses" row/tile.

### 3. Passwordless / OTP Rule
**Strict Constraint**: The application uses passwordless phone OTP authentication.
- Never add password entry, "Change Password", or old password fields.
- The "Sign-in & Security" tile must explicitly disclose OTP authentication (`"Protected by 6-digit phone OTP"`).

### 4. Background Header Art
Incorporate the approved asset:
- Path: `assets/backgrounds/premium/role_selection_background.webp` (or `home_background.webp`).
- Blend with a subtle teal gradient overlay (`Colors.white.withOpacity(0.85)` to `Colors.white`) so text contrast is pristine.

---

## 5. Verification Commands for the Incoming Agent

### Step 1: Run the Targeted Unit/Widget Tests
```bash
cd /mnt/d/grepmind-near/apps/mobile && /home/grepmind/projects/flutter-setup/develop/flutter/bin/flutter test test/profile_screen_test.dart
```
*Expected Result: `All 7 tests passed!`*

### Step 2: Build the Authoritative Validation APK
```bash
cd /mnt/d/grepmind-near/apps/mobile && /home/grepmind/projects/flutter-setup/develop/flutter/bin/flutter build apk --debug --no-pub --flavor development --dart-define=API_BASE_URL=https://api.abashyaka.com --dart-define=FCM_TEST_OTP_ENABLED=true --dart-define=GOOGLE_SERVER_CLIENT_ID=666331814501-v2vtkg0t27b5ld6edavtqkm8dlkr94l3.apps.googleusercontent.com
```

### Step 3: Emulator Verification
1. Target Customer AVD: `Pixel_8` (`emulator-5554` or `emulator-5560`).
2. Install APK:
   ```powershell
   adb -s emulator-5554 install -r apps\mobile\build\app\outputs\flutter-apk\app-development-debug.apk
   ```
3. Launch app and navigate to tab 5 (Profile).
4. Take screenshot and verify visually against the 2026 Abashyaka Obsidian standards.

### Step 4: Documentation & Git Commit
- Update `AGENTS.md` (mark Screen 17 as `✅ Complete (Verified)` with summary).
- Set the next screen (Screen 18: Service Request Status Tracker).
- Commit with a descriptive message via WSL:
  ```bash
  wsl git commit -m "Implement 2026 Premium Obsidian design system on Screen 17 Customer Profile"
  ```
