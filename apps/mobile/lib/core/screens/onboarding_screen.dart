import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grepmind_mobile/core/providers/app_provider.dart';
import 'package:grepmind_mobile/core/theme/app_theme.dart';
import 'package:grepmind_mobile/core/widgets/premium_card.dart';

/// Phone-number onboarding screen with real OTP flow.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _phoneController = TextEditingController();
  final _otpController = TextEditingController();
  bool _sending = false;
  bool _otpSent = false;
  String? _otpCode; // dev-only: shown for local testing

  @override
  void dispose() {
    _phoneController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  Future<void> _sendOTP() async {
    String phone = _phoneController.text.trim();
    if (phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your phone number')),
      );
      return;
    }
    if (!phone.startsWith('+')) {
      phone = '+91$phone';
    }
    debugPrint('🔵 _sendOTP: starting for $phone');
    setState(() => _sending = true);
    final result = await ref.read(authProvider.notifier).requestOTP(phone);
    debugPrint('🔵 _sendOTP: result = $result, mounted = $mounted');
    if (!mounted) {
      debugPrint('🔴 _sendOTP: not mounted, returning');
      return;
    }
    setState(() {
      debugPrint('🔵 _sendOTP: setState called, result != null = ${result != null}');
      _sending = false;
      if (result != null) {
        _otpSent = true;
        _otpCode = result['otp_code'] as String?; // dev-only
        debugPrint('🔵 _sendOTP: _otpSent = $_otpSent, _otpCode = $_otpCode');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('OTP sent to $phone${_otpCode != null ? ' (code: $_otpCode)' : ''}')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to send OTP. Is the API running?')),
        );
      }
    });
  }

  Future<void> _verifyOTP() async {
    String phone = _phoneController.text.trim();
    if (!phone.startsWith('+')) {
      phone = '+91$phone';
    }
    final code = _otpController.text.trim();
    if (code.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter the OTP code')),
      );
      return;
    }
    setState(() => _sending = true);
    final success = await ref.read(authProvider.notifier).verifyOTP(phone, code);
    if (!mounted) return;
    setState(() => _sending = false);
    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Signed in successfully')),
      );
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid OTP code. Try again.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: kScreenPadding),
            child: PremiumCard(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: AppTheme.primaryContainer,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: const Icon(Icons.phone, color: AppTheme.primary, size: 32),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    !_otpSent ? 'Welcome to Grepmind Near' : 'Verify your phone',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: AppTheme.mainText,
                        ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    !_otpSent
                        ? 'Enter your phone number to sign in. We\'ll send a one-time code.'
                        : 'Enter the 6-digit code sent to ${_phoneController.text.trim()}',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppTheme.secondaryText,
                          height: 1.5,
                        ),
                  ),
                  const SizedBox(height: 28),
                  if (!_otpSent) ...[
                    TextField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Phone number',
                        hintText: '+91 98765 43210',
                        prefixText: '+91 ',
                      ),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      height: 52,
                      child: ElevatedButton(
                        onPressed: _sending ? null : _sendOTP,
                        child: _sending
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Text('Send OTP'),
                      ),
                    ),
                  ] else ...[
                    TextField(
                      controller: _otpController,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      decoration: const InputDecoration(
                        labelText: 'OTP code',
                        hintText: '123456',
                        counterText: '',
                      ),
                    ),
                    if (_otpCode != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          'Dev code: $_otpCode',
                          style: const TextStyle(fontSize: 11, color: AppTheme.secondaryText, fontStyle: FontStyle.italic),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    const SizedBox(height: 20),
                    SizedBox(
                      height: 52,
                      child: ElevatedButton(
                        onPressed: _sending ? null : _verifyOTP,
                        child: _sending
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Text('Verify'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: _sending ? null : () => setState(() => _otpSent = false),
                      child: const Text('Use a different number'),
                    ),
                  ],
                  const SizedBox(height: 16),
                  const TextButton(
                    onPressed: null,
                    child: Text('Need help?', style: TextStyle(color: AppTheme.secondaryText)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
