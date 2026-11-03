import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grepmind_mobile/core/providers/app_provider.dart';
import 'package:grepmind_mobile/core/theme/app_theme.dart';
import 'package:grepmind_mobile/core/widgets/premium_card.dart';

/// Phone-number onboarding screen with the production OTP flow.
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
  String? _otpCode; // Returned by the API only in APP_ENV=local.
  int _resendSeconds = 0;
  Timer? _resendTimer;

  @override
  void dispose() {
    _resendTimer?.cancel();
    _phoneController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  String get _normalizedPhone {
    final input = _phoneController.text.trim().replaceAll(
      RegExp(r'[\s()-]'),
      '',
    );
    final nationalNumber = input.startsWith('+91')
        ? input.substring(3)
        : input.startsWith('91') && input.length == 12
        ? input.substring(2)
        : input;
    return '+91$nationalNumber';
  }

  Future<void> _sendOTP() async {
    if (!RegExp(r'^[6-9]\d{9}$').hasMatch(_normalizedPhone.substring(3))) {
      _showMessage('Enter a valid 10-digit Indian mobile number');
      return;
    }
    setState(() => _sending = true);
    final result = await ref
        .read(authProvider.notifier)
        .requestOTP(_normalizedPhone);
    if (!mounted) return;
    setState(() {
      _sending = false;
      if (result != null) {
        _otpSent = true;
        _otpCode = result['otp_code'] as String?;
        _otpController.clear();
        _startResendCountdown();
      }
    });
    _showMessage(
      result == null
          ? 'Could not send a code. Please try again.'
          : 'Verification code sent.',
    );
  }

  void _startResendCountdown() {
    _resendTimer?.cancel();
    _resendSeconds = 60;
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return timer.cancel();
      if (_resendSeconds <= 1) {
        timer.cancel();
        setState(() => _resendSeconds = 0);
      } else {
        setState(() => _resendSeconds--);
      }
    });
  }

  Future<void> _verifyOTP() async {
    final code = _otpController.text.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      _showMessage('Enter the 6-digit verification code');
      return;
    }
    setState(() => _sending = true);
    final success = await ref
        .read(authProvider.notifier)
        .verifyOTP(_normalizedPhone, code);
    if (!mounted) return;
    setState(() => _sending = false);
    _showMessage(
      success
          ? 'Signed in successfully'
          : 'That code could not be verified. Try again.',
    );
  }

  void _useDifferentNumber() {
    _resendTimer?.cancel();
    setState(() {
      _otpSent = false;
      _otpCode = null;
      _resendSeconds = 0;
      _otpController.clear();
    });
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            kScreenPadding,
            16,
            kScreenPadding,
            28,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    height: 48,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: _otpSent
                          ? IconButton(
                              tooltip: 'Back to phone number',
                              onPressed: _sending ? null : _useDifferentNumber,
                              icon: const Icon(Icons.arrow_back_rounded),
                            )
                          : const SizedBox.shrink(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (!_otpSent)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: Container(
                        height: 190,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: AppTheme.primaryContainer,
                          border: Border.all(color: AppTheme.border),
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: Image.asset(
                          'assets/images/login_welcome.jpg',
                          key: const Key('loginWelcomeImage'),
                          fit: BoxFit.cover,
                        ),
                      ),
                    )
                  else
                    Center(
                      child: Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: AppTheme.primaryContainer,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Icon(
                          Icons.shield_outlined,
                          color: AppTheme.primary,
                          size: 32,
                        ),
                      ),
                    ),
                  const SizedBox(height: 20),
                  Text(
                    _otpSent
                        ? 'Verify your number'
                        : 'Welcome to Grepmind Near',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppTheme.mainText,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _otpSent
                        ? 'Enter the 6-digit code we sent to\n$_normalizedPhone'
                        : 'Discover trusted local shops and services around you.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: AppTheme.secondaryText,
                      height: 1.55,
                    ),
                  ),
                  const SizedBox(height: 22),
                  PremiumCard(
                    padding: const EdgeInsets.all(22),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      child: !_otpSent ? _phoneStep() : _otpStep(),
                    ),
                  ),
                  if (!_otpSent) ...[
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        const Expanded(child: Divider(color: AppTheme.border)),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Text(
                            'OR CONTINUE WITH',
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: AppTheme.secondaryText,
                                  letterSpacing: 1,
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                        ),
                        const Expanded(child: Divider(color: AppTheme.border)),
                      ],
                    ),
                    const SizedBox(height: 14),
                    OutlinedButton.icon(
                      key: const Key('googleSignInButton'),
                      onPressed: _showGoogleSetupMessage,
                      icon: const _GoogleMark(),
                      label: const Text('Continue with Google'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                        foregroundColor: AppTheme.mainText,
                        side: const BorderSide(color: AppTheme.border),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.lock_outline_rounded,
                        size: 16,
                        color: AppTheme.secondaryText,
                      ),
                      const SizedBox(width: 7),
                      Flexible(
                        child: Text(
                          'Your number stays private and secure',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AppTheme.secondaryText,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  const TextButton(
                    onPressed: null,
                    child: Text(
                      'Need help?',
                      style: TextStyle(color: AppTheme.secondaryText),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _phoneStep() {
    return Column(
      key: const ValueKey('phone-step'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const Key('phoneInput'),
          controller: _phoneController,
          keyboardType: TextInputType.phone,
          textInputAction: TextInputAction.done,
          maxLength: 10,
          decoration: InputDecoration(
            labelText: 'Mobile number',
            hintText: '98765 43210',
            counterText: '',
            prefixIcon: Padding(
              padding: const EdgeInsetsDirectional.only(start: 14, end: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('🇮🇳', style: TextStyle(fontSize: 19)),
                  const SizedBox(width: 7),
                  Text(
                    '+91',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: AppTheme.mainText,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(width: 1, height: 22, color: AppTheme.border),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 18),
        SizedBox(
          height: 54,
          child: ElevatedButton(
            key: const Key('sendOTPButton'),
            onPressed: _sending ? null : _sendOTP,
            child: _sending ? _loadingLabel() : const Text('Continue securely'),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'We’ll send a one-time code to verify your account.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: AppTheme.secondaryText),
        ),
      ],
    );
  }

  void _showGoogleSetupMessage() {
    _showMessage(
      'Google sign-in will be available after secure provider setup. Use phone OTP for now.',
    );
  }

  Widget _otpStep() {
    final digits = _otpController.text;
    return Column(
      key: const ValueKey('otp-step'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          label: '6-digit verification code',
          textField: true,
          child: SizedBox(
            height: 62,
            child: Stack(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: List.generate(6, (index) {
                    final selected =
                        index == digits.length && digits.length < 6;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 120),
                      width: 43,
                      height: 58,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: selected ? AppTheme.primary : AppTheme.border,
                          width: selected ? 1.8 : 1,
                        ),
                      ),
                      child: Text(
                        index < digits.length ? digits[index] : '',
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(
                              color: AppTheme.mainText,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    );
                  }),
                ),
                Positioned.fill(
                  child: Opacity(
                    opacity: 0.01,
                    child: TextField(
                      key: const Key('otpInput'),
                      controller: _otpController,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.done,
                      autofillHints: const [AutofillHints.oneTimeCode],
                      maxLength: 6,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        counterText: '',
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_otpCode != null) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppTheme.secondaryContainer,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              'Local development code: $_otpCode',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppTheme.secondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
        const SizedBox(height: 20),
        SizedBox(
          height: 54,
          child: ElevatedButton(
            key: const Key('verifyOTPButton'),
            onPressed: _sending ? null : _verifyOTP,
            child: _sending
                ? _loadingLabel()
                : const Text('Verify and sign in'),
          ),
        ),
        const SizedBox(height: 10),
        Center(
          child: TextButton(
            onPressed: _sending || _resendSeconds > 0 ? null : _sendOTP,
            child: Text(
              _resendSeconds > 0
                  ? 'Resend code in 00:${_resendSeconds.toString().padLeft(2, '0')}'
                  : 'Resend code',
            ),
          ),
        ),
        Center(
          child: TextButton(
            onPressed: _sending ? null : _useDifferentNumber,
            child: const Text('Use a different number'),
          ),
        ),
      ],
    );
  }

  Widget _loadingLabel() => const SizedBox(
    width: 20,
    height: 20,
    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
  );
}

class _GoogleMark extends StatelessWidget {
  const _GoogleMark();

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 21,
    height: 21,
    child: CustomPaint(painter: _GoogleMarkPainter()),
  );
}

class _GoogleMarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final colors = <Color>[
      const Color(0xFF4285F4),
      const Color(0xFF34A853),
      const Color(0xFFFBBC05),
      const Color(0xFFEA4335),
    ];
    final starts = <double>[-0.52, 1.05, 2.62, 4.19];
    final sweep = 1.48;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.3
      ..strokeCap = StrokeCap.butt;
    for (var i = 0; i < colors.length; i++) {
      stroke.color = colors[i];
      canvas.drawArc(rect.deflate(2), starts[i], sweep, false, stroke);
    }
    final blue = Paint()
      ..color = colors.first
      ..strokeWidth = 3.3
      ..strokeCap = StrokeCap.butt;
    canvas.drawLine(
      Offset(size.width * .53, size.height * .5),
      Offset(size.width, size.height * .5),
      blue,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
