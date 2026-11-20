import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grepmind_mobile/core/screens/onboarding_screen.dart';
import 'package:grepmind_mobile/core/screens/merchant_registration_screen.dart';
import 'package:grepmind_mobile/features/branding/abashyaka_theme.dart';

/// Screen 2 of the Abashyaka Merchant App Collection:
/// "Grow Your Business with Abashyaka"
///
/// Features value propositions, branded storefront artwork, and entry
/// into merchant onboarding/login.
class MerchantWelcomeScreen extends ConsumerWidget {
  const MerchantWelcomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFF9F2), // Abashyaka Warm White
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Top Brand Lockup
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Image.asset(
                    AbashyakaTheme.splashEmblem,
                    height: 48,
                    width: 48,
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(width: 10),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Abashyaka',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF064D3A),
                          letterSpacing: -0.3,
                        ),
                      ),
                      Text(
                        'Merchant Partner',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFFF8A00),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 28),

              // Storefront Hero Card / Illustration matching Screen 2
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: const Color(0xFFE8F5E9)),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x0A000000),
                      blurRadius: 16,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    // Storefront Vector Graphic with Canopy
                    Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF7ED),
                        shape: BoxShape.circle,
                        border: Border.all(color: const Color(0xFFFFEDD5), width: 2),
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.storefront_rounded,
                          size: 64,
                          color: Color(0xFFFF8A00),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Grow Your Business\nwith Abashyaka',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF111827),
                        height: 1.25,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Join local retailers, restaurants and service professionals across Odisha.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: Color(0xFF6B7280),
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Value propositions checklist
                    _buildValueProp(
                      icon: Icons.check_circle_rounded,
                      text: 'Get more customers in your locality',
                    ),
                    const SizedBox(height: 12),
                    _buildValueProp(
                      icon: Icons.check_circle_rounded,
                      text: 'Manage catalog, stock & orders easily',
                    ),
                    const SizedBox(height: 12),
                    _buildValueProp(
                      icon: Icons.check_circle_rounded,
                      text: 'Increase your sales with zero hidden fees',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              // Primary Action: Get Started
              SizedBox(
                height: 54,
                child: FilledButton(
                  key: const Key('merchantGetStartedButton'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF0B6B4A),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 0,
                  ),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const MerchantRegistrationScreen(),
                      ),
                    );
                  },
                  child: const Text(
                    'Get Started',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // Secondary Action: Sign In
              SizedBox(
                height: 50,
                child: OutlinedButton(
                  key: const Key('merchantSignInButton'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF0B6B4A),
                    side: const BorderSide(color: Color(0xFF0B6B4A), width: 1.5),
                    backgroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const OnboardingScreen(
                          initialMerchantMode: true,
                        ),
                      ),
                    );
                  },
                  child: const Text(
                    'Already registered? Sign In',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildValueProp({required IconData icon, required String text}) {
    return Row(
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: const BoxDecoration(
            color: Color(0xFFE8F5E9),
            shape: BoxShape.circle,
          ),
          child: const Center(
            child: Icon(
              Icons.check_rounded,
              size: 16,
              color: Color(0xFF0B6B4A),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1F2937),
            ),
          ),
        ),
      ],
    );
  }
}
