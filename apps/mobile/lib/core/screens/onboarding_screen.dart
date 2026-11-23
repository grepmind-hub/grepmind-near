import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:grepmind_mobile/core/screens/merchant_welcome_screen.dart';
import 'package:grepmind_mobile/features/branding/abashyaka_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grepmind_mobile/core/providers/app_provider.dart';
import 'package:grepmind_mobile/core/theme/app_theme.dart';
import 'package:grepmind_mobile/core/widgets/premium_card.dart';
import 'package:grepmind_mobile/core/notifications/notification_manager.dart';
import 'package:grepmind_mobile/core/network/api_client.dart';
import 'package:grepmind_mobile/core/constants/app_constants.dart';
import 'package:grepmind_mobile/core/models/business.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sms_autofill/sms_autofill.dart';

/// Phone-number onboarding screen with the production OTP flow.
class OnboardingScreen extends ConsumerStatefulWidget {
  final bool initialMerchantMode;
  const OnboardingScreen({super.key, this.initialMerchantMode = false});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen>
    with CodeAutoFill {
  final _phoneController = TextEditingController();
  final _phoneFocusNode = FocusNode();
  final _otpController = TextEditingController();
  final _otpFocusNode = FocusNode();
  late bool _isMerchantMode;
  bool _sending = false;
  bool _otpSent = false;
  bool _otpRequestInFlight = false;
  bool _verifyingOtp = false;
  String? _pendingAutofillCode;
  String? _challengeId;
  int _resendSeconds = 0;
  Timer? _resendTimer;

  static const String _googleServerClientId = String.fromEnvironment(
    'GOOGLE_SERVER_CLIENT_ID',
  );

  final GoogleSignIn _googleSignIn = GoogleSignIn.instance;
  static Future<void>? _googleInitialization;

  @override
  void initState() {
    super.initState();
    _isMerchantMode = widget.initialMerchantMode;
    _otpController.addListener(_onOtpChanged);
    NotificationManager().onOtpReceived = (payload) {
      if (!mounted) return;
      if (_otpRequestInFlight) {
        return;
      }
      if (_otpSent &&
          payload.matchesChallenge(
            _challengeId,
            _normalizedPhone,
            DateTime.now(),
          )) {
        // Notification verified
      }
    };
  }

  void _onOtpChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _otpController.removeListener(_onOtpChanged);
    _resendTimer?.cancel();
    NotificationManager().onOtpReceived = null;
    cancel();
    _phoneController.dispose();
    _phoneFocusNode.dispose();
    _otpController.dispose();
    _otpFocusNode.dispose();
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
    FocusScope.of(context).unfocus();
    _otpRequestInFlight = true;
    _pendingAutofillCode = null;
    setState(() {
      _sending = true;
    });
    try {
      listenForCode();
    } catch (_) {
      // Keep manual entry available when Retriever is unavailable.
    }
    // Register device pre-login.
    if (const bool.fromEnvironment('FCM_TEST_OTP_ENABLED')) {
      try {
        final installationId = await NotificationManager().getInstallationId();
        final fcmToken = await NotificationManager().getFcmToken();
        if (installationId != null && fcmToken != null) {
          await apiClient.post(
            '/devices/register-prelogin',
            data: {
              'installation_id': installationId,
              'fcm_token': fcmToken,
              'platform': 'android',
              'environment': const String.fromEnvironment(
                'FIREBASE_ENVIRONMENT',
                defaultValue: 'qa',
              ),
              'notification_permission': true,
            },
          );
        }
      } catch (_) {
        // Pre-login registration failure must not block login.
      }
    }
    final result = await ref
        .read(authProvider.notifier)
        .requestOTP(_normalizedPhone);
    if (!mounted) return;
    setState(() {
      _sending = false;
      _otpRequestInFlight = false;
      if (result != null) {
        _otpSent = true;
        _challengeId = result['challenge_id'] as String?;
        _otpController.clear();
        final autofilled = _pendingAutofillCode;
        if (autofilled != null && RegExp(r'^\d{6}$').hasMatch(autofilled)) {
          _setOtpCode(autofilled, notify: false);
        }
        _startResendCountdown();
      }
      _pendingAutofillCode = null;
    });
    if (result != null) {
      _focusOtpInput();
    }
    if (result == null) cancel();
    final lastErr = ref.read(authProvider.notifier).lastOtpError;
    _showMessage(
      result == null
          ? (lastErr ?? 'Could not send a code. Please try again.')
          : 'Verification code sent.',
    );
  }

  void _focusOtpInput({bool clearIfFull = false}) {
    if (clearIfFull && _otpController.text.length == 6) {
      _otpController.clear();
    }
    _otpFocusNode.unfocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _otpFocusNode.requestFocus();
        _otpController.selection = TextSelection.collapsed(
          offset: _otpController.text.length,
        );
        SystemChannels.textInput.invokeMethod('TextInput.show');
      }
    });
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
    if (_sending || _verifyingOtp) return;
    final code = _otpController.text.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      _showMessage('Enter the 6-digit verification code');
      return;
    }
    setState(() {
      _sending = true;
      _verifyingOtp = true;
    });
    final success = await ref
        .read(authProvider.notifier)
        .verifyOTP(
          _normalizedPhone,
          code,
          challengeId: _challengeId,
          preferredRole: _isMerchantMode ? 'merchant' : null,
        );
    if (!mounted) return;
    setState(() {
      _sending = false;
      _verifyingOtp = false;
    });
    _showMessage(
      success
          ? 'Signed in successfully'
          : 'That code could not be verified. Try again.',
    );
  }

  void _useDifferentNumber() {
    FocusScope.of(context).unfocus();
    _resendTimer?.cancel();
    NotificationManager().onOtpReceived = null;
    cancel();
    setState(() {
      _otpSent = false;
      _challengeId = null;
      _resendSeconds = 0;
      _otpController.clear();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _phoneFocusNode.requestFocus();
        _phoneController.selection = TextSelection.collapsed(
          offset: _phoneController.text.length,
        );
        SystemChannels.textInput.invokeMethod('TextInput.show');
      }
    });
  }

  @override
  void codeUpdated() {
    final received = code;
    if (!mounted ||
        received == null ||
        !RegExp(r'^\d{6}$').hasMatch(received)) {
      return;
    }
    if (_otpRequestInFlight) {
      _pendingAutofillCode = received;
      return;
    }
    if (!_otpSent || _verifyingOtp) return;
    _setOtpCode(received);
  }

  void _setOtpCode(String value, {bool notify = true}) {
    _otpController.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
    if (notify) setState(() {});
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) => Theme(
    data: AbashyakaTheme.theme(context),
    child: PopScope<Object?>(
      canPop: !_otpSent,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _otpSent && !_sending) _useDifferentNumber();
      },
      child: Builder(builder: _buildPage),
    ),
  );

  Widget _buildPage(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: AbashyakaTheme.warmWhite,
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
                  if (_otpSent)
                    SizedBox(
                      height: 48,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: IconButton(
                          tooltip: 'Back to phone number',
                          onPressed: _sending ? null : _useDifferentNumber,
                          icon: const Icon(Icons.arrow_back_rounded),
                        ),
                      ),
                    ),
                  if (!_otpSent) ...[
                    Align(
                      child: TextButton.icon(
                        key: const Key('toggleMerchantPartnerLogin'),
                        onPressed: _sending
                            ? null
                            : () {
                                if (_isMerchantMode) {
                                  setState(() => _isMerchantMode = false);
                                } else {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          const MerchantWelcomeScreen(),
                                    ),
                                  );
                                }
                              },
                        icon: Icon(
                          _isMerchantMode
                              ? Icons.person_outline
                              : Icons.storefront_outlined,
                          size: 16,
                          color: _isMerchantMode
                              ? const Color(0xFF0B6B4A)
                              : AppTheme.secondaryText,
                        ),
                        label: Text(
                          _isMerchantMode
                              ? 'Switch to Customer Login'
                              : 'Merchant Partner? Sign in here',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: _isMerchantMode
                                ? const Color(0xFF0B6B4A)
                                : AppTheme.secondaryText,
                          ),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Center(
                    child: Image.asset(
                      AbashyakaTheme.splashEmblem,
                      key: const Key('loginWelcomeImage'),
                      height: 80,
                      width: 80,
                      fit: BoxFit.contain,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _otpSent
                        ? 'Verify OTP'
                        : (_isMerchantMode
                              ? 'Merchant Login'
                              : 'Login / Sign In'),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: AppTheme.mainText,
                      fontSize: 26,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _otpSent
                        ? 'Enter the 6-digit code sent to\n$_normalizedPhone'
                        : 'Enter your mobile number to continue',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: AppTheme.secondaryText,
                      fontSize: 15,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 24),
                  PremiumCard(
                    padding: const EdgeInsets.all(20),
                    child: !_otpSent ? _phoneStep() : _otpStep(),
                  ),
                  if (!_otpSent) ...[
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        const Expanded(child: Divider(color: AppTheme.border)),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Text(
                            'OR',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: AppTheme.secondaryText,
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                        ),
                        const Expanded(child: Divider(color: AppTheme.border)),
                      ],
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      key: const Key('googleSignInButton'),
                      onPressed: _showGoogleSetupMessage,
                      icon: const _GoogleMark(),
                      label: const Text(
                        'Continue with Google',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                        foregroundColor: AppTheme.mainText,
                        backgroundColor: Colors.white,
                        side: const BorderSide(color: AppTheme.border),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  Text(
                    'By continuing, you agree to our',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppTheme.secondaryText,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'Terms & Privacy Policy',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AbashyakaTheme.actionGreen,
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
          focusNode: _phoneFocusNode,
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
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 54),
          child: ElevatedButton(
            key: const Key('sendOTPButton'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AbashyakaTheme.vibrantGreen,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(28),
              ),
            ),
            onPressed: _sending ? null : _sendOTP,
            child: _sending
                ? _loadingLabel()
                : Text(
                    _isMerchantMode ? 'Send OTP' : 'Continue',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
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
    if (_googleServerClientId.isEmpty) {
      _showMessage(
        'Google sign-in will be available after secure provider setup. Use phone OTP for now.',
      );
      return;
    }
    _signInWithGoogle();
  }

  Future<void> _signInWithGoogle() async {
    if (_googleServerClientId.isEmpty) {
      _showMessage('Google OAuth client ID is not configured.');
      return;
    }
    setState(() => _sending = true);
    try {
      await (_googleInitialization ??= _googleSignIn.initialize(
        serverClientId: _googleServerClientId,
      ));
      final account = await _googleSignIn.authenticate();
      final auth = account.authentication;
      final idToken = auth.idToken;
      if (idToken == null) {
        setState(() => _sending = false);
        _showMessage('Could not obtain Google ID token.');
        return;
      }

      // Get installation ID for device association.
      final installationId = await NotificationManager().getInstallationId();
      final fcmToken = await NotificationManager().getFcmToken();

      final response = await apiClient.post(
        '/auth/google/verify',
        data: {
          'id_token': idToken,
          'installation_id': installationId,
          'fcm_token': fcmToken,
          'platform': 'android',
          'environment': const String.fromEnvironment(
            'FIREBASE_ENVIRONMENT',
            defaultValue: 'qa',
          ),
        },
      );

      final data = response.data as Map<String, dynamic>;
      final resultData = data['data'] as Map<String, dynamic>;
      final accessToken = resultData['access_token'] as String;
      final refreshToken = resultData['refresh_token'] as String;
      final userMap = resultData['user'] as Map<String, dynamic>;
      final user = AppUser.fromJson(userMap);

      await ref
          .read(authProvider.notifier)
          .setSession(
            token: accessToken,
            user: user,
            activeRole:
                user.roles.contains('merchant') &&
                    !user.roles.contains('customer')
                ? 'merchant'
                : null,
          );
      await const FlutterSecureStorage().write(
        key: AppConstants.refreshTokenKey,
        value: refreshToken,
      );
      await NotificationManager().registerAfterAuth();

      if (!mounted) return;
      setState(() => _sending = false);
      _showMessage('Signed in successfully');
    } catch (e) {
      _googleInitialization = null;
      if (!mounted) return;
      setState(() => _sending = false);
      _showMessage('Google sign-in failed. Please try again.');
    }
  }

  Widget _otpStep() {
    final digits = _otpController.text;
    return Column(
      key: const ValueKey('otp-step'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _focusOtpInput(),
          child: SizedBox(
            height: 62,
            child: Stack(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: List.generate(6, (index) {
                    final selected = index == digits.length && digits.length < 6;
                    return Flexible(
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 120),
                        width: 43,
                        height: 58,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: selected ? AppTheme.emerald : AppTheme.border,
                            width: selected ? 1.8 : 1,
                          ),
                        ),
                        child: Text(
                          index < digits.length ? digits[index] : '',
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            color: AppTheme.mainText,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    );
                  }),
                ),
                Positioned.fill(
                  child: Opacity(
                    opacity: 0.001,
                    child: TextField(
                      key: const Key('otpInput'),
                      focusNode: _otpFocusNode,
                      controller: _otpController,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.done,
                      autofillHints: const [AutofillHints.oneTimeCode],
                      maxLength: 6,
                      showCursor: false,
                      enableSuggestions: false,
                      autocorrect: false,
                      onTap: () => _focusOtpInput(),
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        counterText: '',
                        isDense: true,
                        filled: false,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (digits.isNotEmpty) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () {
                _otpController.clear();
                _focusOtpInput();
              },
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.backspace_outlined,
                      size: 14,
                      color: AppTheme.secondaryText,
                    ),
                    SizedBox(width: 4),
                    Text(
                      'Clear',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.secondaryText,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: 20),
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 54),
          child: ElevatedButton(
            key: const Key('verifyOTPButton'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AbashyakaTheme.vibrantGreen,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(28),
              ),
            ),
            onPressed:
                _sending || !RegExp(r'^\d{6}$').hasMatch(_otpController.text)
                ? null
                : _verifyOTP,
            child: _sending
                ? _loadingLabel()
                : const Text(
                    'Verify',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
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
