# Abashyaka entry-screen guidelines

Phase 01A uses the supplied Brand Asset Sheet, Branding Sticker Board, Customer App UI Showcase and Local Services App Showcase. Splash and Onboarding are illustrated within these composite boards. Separate full-resolution screen references were not supplied. The implementation interprets their identity, palette and hierarchy.

The approved launcher source is branding/Branding-logo.png, copied exactly from /mnt/d/abashyaka/Branding-logo.png. Its dimensions are 317 × 322. Preserve its aspect ratio and colors. The 512 × 512 store export is an upscale with square padding. It requires visual approval at store size. The two identically named Asset Sheet variants supplied by the user have identical SHA-256 values, so one is retained. The two Identity Board variants depict different marks and are retained as references. Use the explicitly selected launcher mark.

Use Primary Green #0B6B4A, Orange #FF8A00, Mint #E8F5E9, Warm White #FFF9F2 and Dark Green #064D3A. Orange accents need dark readable text. Green buttons use white text. Entry screens use local Material 3 theme data, 4 dp base spacing, 24 dp page padding, 16 dp control corners, 48 dp minimum targets and 220–500 ms transitions that honor reduced motion. Existing workspace theme data remains independently managed.

Render Abashyaka and the tagline as accessible native text. English tagline is “Everything You Need, Locally.” Odia copy is “ସବୁ ଆବଶ୍ୟକତା, ଆପଣଙ୍କ ପାଖରେ।” Use system font fallback for Odia shaping, checked on Android. Do not include the registered-trademark mark visible on some reference boards.

The introduction uses one generated transparent neighborhood illustration informed by the supplied customer/local-service artwork. It conveys shops, groceries and local professionals. Text stays outside the bitmap. No ratings, delivery estimates, availability guarantees, passenger rides, pharmacy fulfillment or doctor booking claims are introduced.

Production PNGs live under apps/mobile/assets/abashyaka/. Composite boards are reference-only. The empty icons and screens directories reserve the requested organization for future supplied exports. Customer, Merchant, Rider and Admin showcases describe visual concepts and do not establish working feature acceptance.
