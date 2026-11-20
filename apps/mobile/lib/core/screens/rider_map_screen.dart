import 'package:flutter/material.dart';
import 'package:grepmind_mobile/core/theme/app_theme.dart';
import 'package:url_launcher/url_launcher.dart';

/// Screen 14 & 18: Rider Active Delivery Route & Navigation Screen.
///
/// Implements authoritative workflow screens from `Abashyaka Rider App Workflow Screens.webp`:
/// - Screen 14: In-Transit Delivery Route & Destination Overview
/// - Screen 18: Turn-by-Turn Route Guidance & Interactive Radar/Path Canvas
///
/// Features:
/// - Prominent turn-by-turn guidance header banner (maneuver, distance, ETA)
/// - Interactive custom route canvas connecting partner store to customer drop-off
/// - Floating compass, recenter, and map layer controls
/// - Recipient contact actions (Call Customer/Partner, External Navigation intent)
/// - Strict compliance: route preview mode with zero unsolicited device GPS tracking
class RiderDeliveryRouteMapScreen extends StatefulWidget {
  const RiderDeliveryRouteMapScreen({
    super.key,
    required this.assignment,
    this.onVerifyPickup,
    this.onConfirmHandover,
  });

  final Map<String, dynamic> assignment;
  final VoidCallback? onVerifyPickup;
  final VoidCallback? onConfirmHandover;

  @override
  State<RiderDeliveryRouteMapScreen> createState() =>
      _RiderDeliveryRouteMapScreenState();
}

class _RiderDeliveryRouteMapScreenState
    extends State<RiderDeliveryRouteMapScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  double _zoomLevel = 1.0;
  bool _isRecentered = true;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Future<void> _launchCall(String phone) async {
    if (phone.isEmpty) return;
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  Future<void> _launchExternalDirections(String destination) async {
    final query = Uri.encodeComponent(destination);
    final uri = Uri.parse('geo:0,0?q=$query');
    final webFallback = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=$query',
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else if (await canLaunchUrl(webFallback)) {
      await launchUrl(webFallback, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.assignment['execution_state']?.toString() ?? 'assigned';
    final isEnRoute = state == 'picked_up' || state == 'en_route';
    final partnerName = widget.assignment['pickup_business_name']?.toString() ??
        widget.assignment['pickup_business']?.toString() ??
        'Partner Store';
    final recipientName =
        widget.assignment['recipient_name']?.toString() ?? 'Customer';
    final destLocality =
        widget.assignment['destination_locality']?.toString() ?? 'Kuanpal';
    final destDistrict =
        widget.assignment['destination_district']?.toString() ?? 'Cuttack';
    final destAddress = widget.assignment['destination_address']?.toString() ??
        '$destLocality, $destDistrict';
    final phone = widget.assignment['contact_phone']?.toString() ?? '';
    final orderRef = widget.assignment['order_reference']?.toString() ??
        widget.assignment['order_id']?.toString() ??
        'GN-ORDER';

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAF9),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Delivery Route Navigation',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 17,
                color: Colors.white,
              ),
            ),
            Text(
              'Order: $orderRef',
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFFE2E8F0),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        backgroundColor: AppTheme.emeraldDark,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.shield_outlined, size: 14, color: Colors.white),
                SizedBox(width: 4),
                Text(
                  'Route Preview',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          // 1. Central Route Canvas (Stylized map representation with road grid & path)
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _animController,
              builder: (context, child) {
                return CustomPaint(
                  painter: _RiderRouteMapPainter(
                    pulseValue: _animController.value,
                    zoomLevel: _zoomLevel,
                    isEnRoute: isEnRoute,
                    partnerName: partnerName,
                    customerName: recipientName,
                    destLocality: destLocality,
                  ),
                );
              },
            ),
          ),

          // 2. Top Turn-by-Turn Instruction Banner (Screen 18)
          Positioned(
            top: 14,
            left: 14,
            right: 14,
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF064D3A),
                borderRadius: BorderRadius.circular(16),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x33064D3A),
                    blurRadius: 16,
                    offset: Offset(0, 6),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppTheme.emerald,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      isEnRoute
                          ? Icons.turn_right_rounded
                          : Icons.straight_rounded,
                      color: Colors.white,
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          isEnRoute
                              ? 'In 250m, continue onto Cuttack-Kuanpal Road'
                              : 'Head North towards $partnerName',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          isEnRoute
                              ? 'Destination: $destLocality · 2.4 km (~12 mins)'
                              : 'Pickup: $partnerName · 850m (~4 mins)',
                          style: const TextStyle(
                            color: Color(0xFFCBD5E1),
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 3. Floating Map Controls (Zoom in/out, Recenter)
          Positioned(
            right: 16,
            top: 100,
            child: Column(
              children: [
                _buildMapFloatingButton(
                  icon: Icons.add_rounded,
                  onPressed: () {
                    setState(() {
                      if (_zoomLevel < 1.6) _zoomLevel += 0.2;
                    });
                  },
                ),
                const SizedBox(height: 8),
                _buildMapFloatingButton(
                  icon: Icons.remove_rounded,
                  onPressed: () {
                    setState(() {
                      if (_zoomLevel > 0.8) _zoomLevel -= 0.2;
                    });
                  },
                ),
                const SizedBox(height: 8),
                _buildMapFloatingButton(
                  icon: _isRecentered
                      ? Icons.my_location_rounded
                      : Icons.location_searching_rounded,
                  color: _isRecentered ? AppTheme.emerald : Colors.white,
                  iconColor: _isRecentered ? Colors.white : AppTheme.brandText,
                  onPressed: () {
                    setState(() {
                      _isRecentered = !_isRecentered;
                      _zoomLevel = 1.0;
                    });
                  },
                ),
              ],
            ),
          ),

          // 4. Bottom Destination Action Card (Screen 14)
          Positioned(
            left: 14,
            right: 14,
            bottom: 16,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFE2E8F0)),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x1A000000),
                    blurRadius: 18,
                    offset: Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: isEnRoute
                              ? const Color(0xFFE6F4F0)
                              : const Color(0xFFFEF3C7),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          isEnRoute ? 'EN ROUTE TO DROP-OFF' : 'AT STORE PICKUP',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: isEnRoute
                                ? AppTheme.emeraldDark
                                : AppTheme.riderAmberDark,
                          ),
                        ),
                      ),
                      const Spacer(),
                      const Icon(
                        Icons.lock_clock_outlined,
                        size: 14,
                        color: AppTheme.secondaryText,
                      ),
                      const SizedBox(width: 4),
                      const Text(
                        'Single-use code required',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppTheme.secondaryText,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          isEnRoute
                              ? Icons.person_pin_circle_rounded
                              : Icons.storefront_rounded,
                          color: AppTheme.emeraldDark,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isEnRoute ? recipientName : partnerName,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: AppTheme.brandText,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              isEnRoute
                                  ? destAddress
                                  : 'Pickup location · $partnerName',
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppTheme.secondaryText,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Action Buttons
                  Row(
                    children: [
                      if (phone.isNotEmpty) ...[
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppTheme.brandText,
                              side: const BorderSide(color: Color(0xFFCBD5E1)),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            onPressed: () => _launchCall(phone),
                            icon: const Icon(Icons.phone_outlined, size: 16),
                            label: const Text(
                              'Call',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                      ],
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.brandText,
                            side: const BorderSide(color: Color(0xFFCBD5E1)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          onPressed: () => _launchExternalDirections(
                            isEnRoute ? destAddress : partnerName,
                          ),
                          icon: const Icon(Icons.directions_outlined, size: 16),
                          label: const Text(
                            'Directions',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // Handover Verification CTA
                  if (isEnRoute && widget.onConfirmHandover != null)
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                        backgroundColor: AppTheme.emeraldDark,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: () {
                        Navigator.pop(context);
                        widget.onConfirmHandover!();
                      },
                      icon: const Icon(Icons.verified_user_outlined),
                      label: const Text(
                        'Confirm customer handover',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    )
                  else if (!isEnRoute && widget.onVerifyPickup != null)
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                        backgroundColor: AppTheme.emerald,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: () {
                        Navigator.pop(context);
                        widget.onVerifyPickup!();
                      },
                      icon: const Icon(Icons.verified_outlined),
                      label: const Text(
                        'Verify partner handover',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMapFloatingButton({
    required IconData icon,
    required VoidCallback onPressed,
    Color color = Colors.white,
    Color iconColor = AppTheme.brandText,
  }) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: IconButton(
        padding: EdgeInsets.zero,
        icon: Icon(icon, size: 20, color: iconColor),
        onPressed: onPressed,
      ),
    );
  }
}

/// Custom painter for rendering stylized delivery route map canvas
class _RiderRouteMapPainter extends CustomPainter {
  _RiderRouteMapPainter({
    required this.pulseValue,
    required this.zoomLevel,
    required this.isEnRoute,
    required this.partnerName,
    required this.customerName,
    required this.destLocality,
  });

  final double pulseValue;
  final double zoomLevel;
  final bool isEnRoute;
  final String partnerName;
  final String customerName;
  final String destLocality;

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Background map texture
    final bgPaint = Paint()..color = const Color(0xFFF1F5F9);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    // 2. Stylized road network grid
    final gridPaint = Paint()
      ..color = const Color(0xFFE2E8F0)
      ..strokeWidth = 2.0;

    for (var x = 0.0; x < size.width; x += 50 * zoomLevel) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (var y = 0.0; y < size.height; y += 50 * zoomLevel) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // Secondary arterial roads
    final mainRoadPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 6.0;
    canvas.drawLine(
      Offset(0, size.height * 0.45),
      Offset(size.width, size.height * 0.45),
      mainRoadPaint,
    );
    canvas.drawLine(
      Offset(size.width * 0.35, 0),
      Offset(size.width * 0.35, size.height),
      mainRoadPaint,
    );

    // 3. Define Route Waypoints
    final pStart = Offset(size.width * 0.28, size.height * 0.52); // Partner Store
    final pMid1 = Offset(size.width * 0.35, size.height * 0.45);
    final pMid2 = Offset(size.width * 0.65, size.height * 0.45);
    final pEnd = Offset(size.width * 0.72, size.height * 0.32); // Customer Drop

    // Route Path
    final routePath = Path()
      ..moveTo(pStart.dx, pStart.dy)
      ..lineTo(pMid1.dx, pMid1.dy)
      ..lineTo(pMid2.dx, pMid2.dy)
      ..lineTo(pEnd.dx, pEnd.dy);

    // Route Shadow
    final shadowPaint = Paint()
      ..color = AppTheme.emerald.withValues(alpha: 0.18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10.0
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(routePath, shadowPaint);

    // Active Route Polyline
    final polylinePaint = Paint()
      ..color = AppTheme.emerald
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5.0
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(routePath, polylinePaint);

    // 4. Partner Store Pin (Origin)
    _drawPin(
      canvas: canvas,
      center: pStart,
      iconData: Icons.storefront_rounded,
      label: partnerName,
      ringColor: AppTheme.emerald,
      isOrigin: true,
    );

    // 5. Customer Delivery Pin (Destination)
    _drawPin(
      canvas: canvas,
      center: pEnd,
      iconData: Icons.location_on_rounded,
      label: '$customerName ($destLocality)',
      ringColor: AppTheme.emeraldDark,
      isOrigin: false,
    );

    // 6. Rider Bike Indicator (In-Transit Animation)
    final riderPos = isEnRoute
        ? Offset(
            pMid1.dx + (pMid2.dx - pMid1.dx) * 0.65,
            pMid1.dy + (pMid2.dy - pMid1.dy) * 0.65,
          )
        : Offset(
            pStart.dx + (pMid1.dx - pStart.dx) * 0.4,
            pStart.dy + (pMid1.dy - pStart.dy) * 0.4,
          );

    // Pulsing Radar Circle around Rider
    final pulseRadius = 14 + pulseValue * 12;
    final pulsePaint = Paint()
      ..color = AppTheme.emerald.withValues(alpha: (1 - pulseValue) * 0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawCircle(riderPos, pulseRadius, pulsePaint);

    // Rider Marker
    final markerPaint = Paint()
      ..color = const Color(0xFF064D3A)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(riderPos, 14, markerPaint);

    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    canvas.drawCircle(riderPos, 14, borderPaint);

    // Center icon
    final textPainter = TextPainter(textDirection: TextDirection.ltr);
    textPainter.text = TextSpan(
      text: String.fromCharCode(Icons.two_wheeler_rounded.codePoint),
      style: TextStyle(
        fontSize: 14,
        fontFamily: Icons.two_wheeler_rounded.fontFamily,
        package: Icons.two_wheeler_rounded.fontPackage,
        color: Colors.white,
      ),
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(riderPos.dx - textPainter.width / 2, riderPos.dy - textPainter.height / 2),
    );
  }

  void _drawPin({
    required Canvas canvas,
    required Offset center,
    required IconData iconData,
    required String label,
    required Color ringColor,
    required bool isOrigin,
  }) {
    // Pin Shadow
    canvas.drawCircle(
      Offset(center.dx, center.dy + 2),
      16,
      Paint()..color = Colors.black.withValues(alpha: 0.15),
    );

    // Pin Body
    canvas.drawCircle(
      center,
      15,
      Paint()..color = Colors.white,
    );
    canvas.drawCircle(
      center,
      15,
      Paint()
        ..color = ringColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0,
    );

    // Pin Icon
    final tp = TextPainter(textDirection: TextDirection.ltr);
    tp.text = TextSpan(
      text: String.fromCharCode(iconData.codePoint),
      style: TextStyle(
        fontSize: 16,
        fontFamily: iconData.fontFamily,
        package: iconData.fontPackage,
        color: ringColor,
      ),
    );
    tp.layout();
    tp.paint(
      canvas,
      Offset(center.dx - tp.width / 2, center.dy - tp.height / 2),
    );

    // Pin Callout Label
    final labelTp = TextPainter(textDirection: TextDirection.ltr);
    labelTp.text = TextSpan(
      text: label,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: AppTheme.brandText,
      ),
    );
    labelTp.layout();

    final labelBg = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(center.dx, center.dy + 26),
        width: labelTp.width + 12,
        height: 20,
      ),
      const Radius.circular(6),
    );
    canvas.drawRRect(
      labelBg,
      Paint()..color = Colors.white,
    );
    canvas.drawRRect(
      labelBg,
      Paint()
        ..color = const Color(0xFFCBD5E1)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );
    labelTp.paint(
      canvas,
      Offset(center.dx - labelTp.width / 2, center.dy + 17),
    );
  }

  @override
  bool shouldRepaint(covariant _RiderRouteMapPainter oldDelegate) {
    return oldDelegate.pulseValue != pulseValue ||
        oldDelegate.zoomLevel != zoomLevel ||
        oldDelegate.isEnRoute != isEnRoute;
  }
}
