import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:grepmind_mobile/core/notifications/notification_manager.dart';

/// Foreground OTP notification banner matching the approved Abashyaka design.
///
/// Displayed near the top of the OTP verification screen when an FCM data
/// message carrying a test OTP is received. The banner is shown only while
/// the app is foregrounded and never exposed on the Android lock screen
/// (data-only FCM messages).
class OtpNotificationBanner extends StatefulWidget {
  const OtpNotificationBanner({super.key, required this.payload, this.onCopy});

  final FcmOtpPayload payload;
  final ValueChanged<String>? onCopy;

  @override
  State<OtpNotificationBanner> createState() => _OtpNotificationBannerState();
}

class _OtpNotificationBannerState extends State<OtpNotificationBanner> {
  Timer? _expiryTimer;

  void _scheduleExpiry() {
    _expiryTimer?.cancel();
    final remaining = widget.payload.expiresAt.difference(DateTime.now());
    if (!remaining.isNegative && remaining > Duration.zero) {
      _expiryTimer = Timer(remaining, () {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _scheduleExpiry();
  }

  @override
  void didUpdateWidget(covariant OtpNotificationBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    _scheduleExpiry();
  }

  @override
  void dispose() {
    _expiryTimer?.cancel();
    super.dispose();
  }

  bool get _isExpired => widget.payload.expiresAt.isBefore(DateTime.now());

  @override
  Widget build(BuildContext context) {
    if (_isExpired) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFE8F5E9), // Light green background
        borderRadius: BorderRadius.circular(16), // Rounded corners
        border: Border.all(color: const Color(0xFFC8E6C9)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header: app icon, name, timestamp
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: const Color(0xFF123D36), // Forest green
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Center(
                  child: Text(
                    'A',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Abashyaka',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF172033),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Just now',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.green.shade600,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // OTP message
          Text.rich(
            TextSpan(
              text: 'Your verification code is ',
              style: const TextStyle(
                fontSize: 16,
                color: Color(0xFF172033),
                fontWeight: FontWeight.w600,
              ),
              children: [
                TextSpan(
                  text: ' ${widget.payload.otpCode}',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0B6B4A), // Emerald
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Valid for 5 minutes. Do not share this code.',
            style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
          ),
          const SizedBox(height: 14),
          // Copy OTP action
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              OutlinedButton.icon(
                onPressed: _copyOtp,
                icon: const Icon(
                  Icons.copy,
                  size: 16,
                  color: Color(0xFF0B6B4A),
                ),
                label: const Text(
                  'Copy OTP',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF0B6B4A),
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF0B6B4A),
                  side: const BorderSide(color: Color(0xFF0B6B4A)),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _copyOtp() async {
    if (_isExpired) return;
    widget.onCopy?.call(widget.payload.otpCode);
    await Clipboard.setData(ClipboardData(text: widget.payload.otpCode));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('OTP copied to clipboard'),
        duration: Duration(seconds: 2),
        backgroundColor: Color(0xFF0B6B4A),
      ),
    );
    // Do not automatically submit the code.
  }
}
