import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grepmind_mobile/core/screens/onboarding_screen.dart';
import 'package:grepmind_mobile/core/screens/splash_screen.dart';
import 'package:grepmind_mobile/features/branding/abashyaka_theme.dart';
import 'package:grepmind_mobile/features/onboarding/introduction_preferences.dart';

/// Mounted only after the app has finished restoring an unauthenticated session.
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
    if (_showLogin) return const OnboardingScreen();
    return FutureBuilder<bool>(
      future: _preference,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const SplashScreen();
        }
        if (snapshot.data == true) return const OnboardingScreen();
        return Theme(
          data: AbashyakaTheme.theme(context),
          child: Builder(
            builder: (context) => Scaffold(
              backgroundColor: AbashyakaTheme.warmWhite,
              body: SafeArea(
                child: LayoutBuilder(
                  builder: (context, constraints) => Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 520),
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AbashyakaTheme.pagePadding,
                          vertical: 16,
                        ),
                        child: Column(
                          children: [
                            const SizedBox(height: 8),
                            ExcludeSemantics(
                              child: Image.asset(
                                AbashyakaTheme.onboardingHero,
                                height: (constraints.maxHeight * .38).clamp(
                                  180,
                                  320,
                                ),
                                width: double.infinity,
                                fit: BoxFit.contain,
                                cacheWidth: 960,
                              ),
                            ),
                            const SizedBox(height: 20),
                            Semantics(
                              header: true,
                              child: Text(
                                'All Your Needs\nin One App',
                                textAlign: TextAlign.center,
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineMedium
                                    ?.copyWith(
                                      fontWeight: FontWeight.w800,
                                      height: 1.2,
                                      letterSpacing: -.5,
                                      color: AbashyakaTheme.text,
                                    ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'Shop, book services, ride,\nget medicines and more,\nfrom nearby businesses.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 15,
                                height: 1.45,
                                color: AbashyakaTheme.muted,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 24),
                            // 3-dot pagination indicator
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: const BoxDecoration(
                                    color: AbashyakaTheme.green,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: const BoxDecoration(
                                    color: Color(0xFFD1D5DB),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: const BoxDecoration(
                                    color: Color(0xFFD1D5DB),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 28),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton(
                                key: const Key('getStartedButton'),
                                onPressed: _saving ? null : _getStarted,
                                style: FilledButton.styleFrom(
                                  backgroundColor: AbashyakaTheme.green,
                                  foregroundColor: Colors.white,
                                  minimumSize: const Size.fromHeight(54),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(27),
                                  ),
                                ),
                                child: Text(
                                  _saving ? 'Opening sign in…' : 'Get started',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextButton(
                              onPressed: _saving ? null : _getStarted,
                              child: const Text(
                                'Skip',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: AbashyakaTheme.muted,
                                ),
                              ),
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
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
