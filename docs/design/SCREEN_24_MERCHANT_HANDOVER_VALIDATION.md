# Screen 24 Merchant Pickup & Rider Handover

In **Merchant Workspace → Orders**, expand a ready-for-pickup order with dispatch data. The V2.0 handover panel groups the rider and delivery status with the existing pickup-code action. The confirmation and code dialogs use white surfaces, teal actions, and scrollable content. The expiry label can wrap at narrow widths.

The change is presentation-only. Rider-arrival eligibility, authorization, dispatch refresh, code issuance, expiry, and verification remain as implemented. No live pickup code was issued.

Targeted Dart analysis reported no issues. All eight order pipeline and Merchant order widget tests passed, including rider arrival, pickup-code display and clearing, backend denial, and duplicate submission protection.

Live acceptance is **PARTIAL** and requires a ready-for-pickup test order with an assigned rider. This UI pass did not produce a new APK.
