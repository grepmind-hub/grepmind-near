import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grepmind_mobile/core/providers/app_provider.dart';
import 'package:grepmind_mobile/core/screens/admin_portal_screen.dart';
import 'package:grepmind_mobile/core/screens/onboarding_screen.dart';
import 'package:grepmind_mobile/core/screens/role_selection_screen.dart';
import 'package:grepmind_mobile/core/screens/splash_screen.dart';
import 'package:grepmind_mobile/core/widgets/metallic_button.dart';
import 'package:grepmind_mobile/features/branding/abashyaka_theme.dart';
import 'package:grepmind_mobile/features/onboarding/introduction_preferences.dart';
import 'package:grepmind_mobile/main.dart';

/// Screen 03: Get Started / Onboarding Screen.
///
/// Implements the approved Metallic Teal Fluid Wave + Pearl White UI.
/// - Top fluid wave header
/// - Top-right rounded white Skip button
/// - Large seamless 3D illustration (Storefront + Delivery pro with grocery bag)
/// - Bold "Everything Local At Your Doorstep" heading
/// - "Discover shops, book services, order food & grocery — all in one app." subtitle
/// - 3-dot pagination indicator (metallic teal active pill)
/// - Full-width glossy MetallicButton "Get started"
class IntroductionScreen extends ConsumerStatefulWidget {
  const IntroductionScreen({super.key});

  @override
  ConsumerState<IntroductionScreen> createState() => _IntroductionScreenState();
}

class _IntroductionScreenState extends ConsumerState<IntroductionScreen> {
  late Future<bool> _preference;
  bool _showLogin = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _preference = ref.read(introductionPreferencesProvider).isComplete();
  }

  Future<void> _getStarted() async {
    if (_saving || _showLogin) return;
    setState(() => _saving = true);
    try {
      await ref.read(introductionPreferencesProvider).complete();
    } catch (_) {
      // A presentation preference must not prevent normal OTP authentication.
    }
    if (mounted) {
      setState(() {
        _showLogin = true;
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    if (authState.isAuthenticated) {
      final activeRole = authState.activeRole;
      if (activeRole == null) {
        return const RoleSelectionScreen();
      } else if (activeRole == 'admin') {
        return const AdminPortalScreen();
      } else {
        return MainNavigator(
          key: ValueKey('workspace-$activeRole'),
          activeRole: activeRole,
        );
      }
    }

    if (_showLogin) return const OnboardingScreen();

    return FutureBuilder<bool>(
      future: _preference,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const SplashScreen.dark();
        }
        if (snapshot.data == true) return const OnboardingScreen();

        return Theme(
          data: AbashyakaTheme.theme(context),
          child: Scaffold(
            backgroundColor: AbashyakaColors.pearlWhite,
            body: Stack(
              children: [
                // Background: Approved Full-Screen Metallic Wave Canvas from bg-3.webp
                Positioned.fill(
                  child: Container(
                    decoration: const BoxDecoration(
                      image: DecorationImage(
                        image: AssetImage(
                          'assets/backgrounds/premium/onboarding_background.webp',
                        ),
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ),

                // Main Foreground Content
                SafeArea(
                  child: LayoutBuilder(
                    builder: (context, constraints) => Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 520),
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AbashyakaSpacing.screenHorizontal,
                            vertical: 12,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              // Top Bar with Skip button aligned right
                              Align(
                                alignment: Alignment.topRight,
                                child: InkWell(
                                  key: const Key('skipButton'),
                                  onTap: _saving ? null : _getStarted,
                                  borderRadius: BorderRadius.circular(16),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 7,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AbashyakaColors.pureWhite,
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: AbashyakaColors.silverGlass,
                                        width: 1.2,
                                      ),
                                      boxShadow: const [
                                        BoxShadow(
                                          color: Color(0x0A003F46),
                                          blurRadius: 6,
                                          offset: Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    child: Text(
                                      'Skip',
                                      style:
                                          AbashyakaTypography.categoryLabel(
                                            color: AbashyakaColors.inkBlack,
                                          ).copyWith(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),

                              // Central Large Seamless 3D Illustration
                              ExcludeSemantics(
                                child: Image.asset(
                                  'assets/illustrations/onboarding_local_3d.webp',
                                  height: (constraints.maxHeight * 0.38).clamp(
                                    160.0,
                                    310.0,
                                  ),
                                  width: double.infinity,
                                  fit: BoxFit.contain,
                                  errorBuilder: (_, __, ___) => Image.asset(
                                    'assets/abashyaka/onboarding_3d_phone.png',
                                    height: (constraints.maxHeight * 0.38)
                                        .clamp(160.0, 310.0),
                                    fit: BoxFit.contain,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 24),

                              // Heading: Everything Local At Your Doorstep
                              Semantics(
                                header: true,
                                child: Text(
                                  'Everything Local\nAt Your Doorstep',
                                  textAlign: TextAlign.center,
                                  style:
                                      AbashyakaTypography.displayHeading(
                                        fontSize: 27,
                                        color: AbashyakaColors.inkBlack,
                                      ).copyWith(
                                        height: 1.25,
                                        letterSpacing: -0.5,
                                        fontWeight: FontWeight.w800,
                                      ),
                                ),
                              ),
                              const SizedBox(height: 12),

                              // Subtitle
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                ),
                                child: Text(
                                  'Discover shops, book services, order food & grocery — all in one app.',
                                  textAlign: TextAlign.center,
                                  style: AbashyakaTypography.supportingText(
                                    fontSize: 14.5,
                                    color: AbashyakaColors.secondaryText,
                                  ).copyWith(height: 1.45),
                                ),
                              ),
                              const SizedBox(height: 24),

                              // 3-dot pagination indicator (polished metallic teal active pill)
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Container(
                                    width: 24,
                                    height: 6,
                                    decoration: BoxDecoration(
                                      color: AbashyakaColors.metallicTeal,
                                      borderRadius: BorderRadius.circular(3),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Container(
                                    width: 6,
                                    height: 6,
                                    decoration: const BoxDecoration(
                                      color: AbashyakaColors.silverGlass,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Container(
                                    width: 6,
                                    height: 6,
                                    decoration: const BoxDecoration(
                                      color: AbashyakaColors.silverGlass,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 28),

                              // Glossy MetallicButton "Get started"
                              MetallicButton(
                                buttonKey: const Key('getStartedButton'),
                                text: 'Get started',
                                trailingIcon: const Icon(
                                  Icons.arrow_forward_rounded,
                                  color: Colors.white,
                                  size: 18,
                                ),
                                isLoading: _saving,
                                onPressed: _saving ? null : _getStarted,
                              ),
                              if (snapshot.hasError)
                                Padding(
                                  padding: const EdgeInsets.only(top: 16),
                                  child: TextButton.icon(
                                    onPressed: () => setState(() {
                                      _preference = ref
                                          .read(introductionPreferencesProvider)
                                          .isComplete();
                                    }),
                                    icon: const Icon(Icons.refresh),
                                    label: const Text(
                                      'Could not load your welcome preference. Retry',
                                    ),
                                  ),
                                ),
                              const SizedBox(height: 16),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
