import 'package:flutter/material.dart';

/// Centralized Spacing, Radius, and Shadow tokens for Abashyaka.
abstract final class AbashyakaSpacing {
  static const double xxs = 4.0;
  static const double xs = 8.0;
  static const double sm = 12.0;
  static const double md = 16.0;
  static const double lg = 24.0;
  static const double xl = 32.0;

  static const double screenHorizontal = 16.0;
  static const double touchTargetMin = 48.0;
}

abstract final class AbashyakaRadius {
  static const double xs = 8.0;
  static const double sm = 12.0;
  static const double md = 16.0;
  static const double lg = 20.0;
  static const double xl = 24.0;
  static const double button = 28.0;
  static const double nav = 28.0;
  static const double search = 26.0;
  static const double categoryCard = 18.0;
  static const double banner = 22.0;
  static const double card16 = 16.0;
  static const double card18 = 18.0;
  static const double card20 = 20.0;
  static const double card24 = 24.0;
}

abstract final class AbashyakaShadows {
  /// Subtle teal shadow for cards and floating components
  static const List<BoxShadow> card = [
    BoxShadow(color: Color(0x0C003F46), blurRadius: 14, offset: Offset(0, 4)),
  ];

  /// Teal tinted shadow for category cards
  static const List<BoxShadow> categoryCard = [
    BoxShadow(color: Color(0x10008C95), blurRadius: 12, offset: Offset(0, 4)),
  ];

  /// Shadow for primary metallic buttons
  static const List<BoxShadow> metallicButton = [
    BoxShadow(color: Color(0x2E00545B), blurRadius: 14, offset: Offset(0, 6)),
  ];

  /// Shadow for floating bottom navigation bar
  static const List<BoxShadow> floatingNav = [
    BoxShadow(color: Color(0x1A003F46), blurRadius: 20, offset: Offset(0, 8)),
  ];

  /// Subtle glow for active controls
  static const List<BoxShadow> aquaGlow = [
    BoxShadow(color: Color(0x4055D6CD), blurRadius: 16, offset: Offset(0, 0)),
  ];
}
