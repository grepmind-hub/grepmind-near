import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grepmind_mobile/core/providers/app_provider.dart';
import 'package:grepmind_mobile/core/models/business.dart';
import 'package:grepmind_mobile/core/theme/app_theme.dart';

/// Screen allowing users to choose their active portal experience (RBAC):
/// - Customer / Explorer
/// - Merchant & Service Pro
/// - Platform Administrator
class RoleSelectionScreen extends ConsumerStatefulWidget {
  final bool isSwitching;

  const RoleSelectionScreen({super.key, this.isSwitching = false});

  @override
  ConsumerState<RoleSelectionScreen> createState() =>
      _RoleSelectionScreenState();
}

class _RoleSelectionScreenState extends ConsumerState<RoleSelectionScreen> {
  late String _selectedRole;
  bool _checkingPermissions = true;
  bool _savingRole = false;
  String? _permissionError;

  @override
  void initState() {
    super.initState();
    final currentActive = ref.read(authProvider).activeRole;
    _selectedRole = currentActive ?? 'customer';
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshPermissions());
  }

  Future<void> _refreshPermissions() async {
    final user = await ref.read(authProvider.notifier).refreshCurrentUser();
    if (!mounted) return;
    setState(() {
      _checkingPermissions = false;
      _permissionError = user == null
          ? 'Could not verify workspace access. Check your connection and retry.'
          : null;
      if (user != null && !_canUseRole(user, _selectedRole)) {
        _selectedRole = user.roles.contains('customer')
            ? 'customer'
            : user.roles.contains('merchant') ||
                  user.roles.contains('professional')
            ? 'merchant'
            : user.roles.contains('rider')
            ? 'rider'
            : user.roles.contains('admin')
            ? 'admin'
            : 'customer';
      }
    });
  }

  bool _canUseRole(AppUser user, String role) {
    switch (role) {
      case 'customer':
        return user.roles.contains('customer');
      case 'merchant':
        return user.roles.contains('merchant') ||
            user.roles.contains('professional');
      case 'rider':
      case 'admin':
        return user.roles.contains(role);
      default:
        return false;
    }
  }

  Future<void> _applyRoleSelection() async {
    setState(() {
      _savingRole = true;
      _permissionError = null;
    });
    final applied = await ref
        .read(authProvider.notifier)
        .setActiveRole(_selectedRole);
    if (!mounted) return;
    setState(() => _savingRole = false);
    if (!applied) {
      setState(
        () => _permissionError = 'This workspace is not authorized for your account. Refresh access and try again.',
      );
      return;
    }

    if (widget.isSwitching) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final user = authState.user;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Select Portal Experience'),
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: AppTheme.mainText,
        leading: widget.isSwitching
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.of(context).pop(),
              )
            : null,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Center(
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: AppTheme.primaryContainer,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(
                    Icons.hub_outlined,
                    color: AppTheme.primary,
                    size: 34,
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'Welcome to Grepmind Near',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: AppTheme.mainText,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Choose how you want to use the platform. You can switch your active role at any time from your Profile settings.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: AppTheme.secondaryText, height: 1.45),
              ),
              if (user != null) ...[
                const SizedBox(height: 14),
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'Signed in as ${user.phoneE164} (${user.roles.join(", ")})',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.secondaryText,
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 28),

              if (_checkingPermissions) ...[
                const LinearProgressIndicator(minHeight: 2),
                const SizedBox(height: 12),
                const Text(
                  'Verifying your workspace access…',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppTheme.secondaryText),
                ),
                const SizedBox(height: 20),
              ],
              if (_permissionError != null) ...[
                Material(
                  color: const Color(0xFFFFF1F2),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.info_outline,
                          color: Color(0xFFBE123C),
                        ),
                        const SizedBox(width: 10),
                        Expanded(child: Text(_permissionError!)),
                        TextButton(
                          onPressed: _checkingPermissions
                              ? null
                              : () {
                                  setState(() => _checkingPermissions = true);
                                  _refreshPermissions();
                                },
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // 1. Customer Option
              _buildRoleCard(
                roleId: 'customer',
                title: 'Customer / Explorer',
                subtitle: 'Discover nearby shops, book certified trades, order daily essentials, and track local service bookings.',
                badgeText: 'Discovery & Orders',
                themeColor: const Color(0xFF2457D6),
                icon: Icons.explore_outlined,
                features: [
                  'Local Shop Directory',
                  'Nearby Interactive Map',
                  'Service Appointments',
                ],
                enabled:
                    !_checkingPermissions &&
                    user != null &&
                    _canUseRole(user, 'customer'),
              ),
              const SizedBox(height: 16),

              // 2. Merchant Option
              _buildRoleCard(
                roleId: 'merchant',
                title: 'Merchant & Service Pro',
                subtitle: 'Manage your storefront listing, accept customer service requests, manage inventory catalog & operating hours.',
                badgeText: 'Business Workspace',
                themeColor: const Color(0xFF0F766E),
                icon: Icons.storefront_outlined,
                features: [
                  'Incoming Service Requests',
                  'Catalog & Pricing',
                  'Store Hours & Radius',
                ],
                enabled:
                    !_checkingPermissions &&
                    user != null &&
                    _canUseRole(user, 'merchant'),
              ),
              const SizedBox(height: 16),

              _buildRoleCard(
                roleId: 'rider',
                title: 'Rider',
                subtitle: 'Delivery workspace for approved rider accounts. Dispatch and tracking tools are not available yet.',
                badgeText: _checkingPermissions
                    ? 'Checking authorization'
                    : user?.roles.contains('rider') == true
                    ? 'Backend approved'
                    : 'Requires backend approval',
                themeColor: const Color(0xFF334155),
                icon: Icons.pedal_bike_outlined,
                features: const [],
                enabled:
                    !_checkingPermissions &&
                    user != null &&
                    _canUseRole(user, 'rider'),
              ),
              const SizedBox(height: 16),

              // 3. Admin Option
              _buildRoleCard(
                roleId: 'admin',
                title: 'Platform Administrator',
                subtitle: 'Audit merchant listings, review business verification claims, resolve customer reports & monitor platform health.',
                badgeText: 'Admin Moderation',
                themeColor: const Color(0xFF7C3AED),
                icon: Icons.admin_panel_settings_outlined,
                features: [
                  'Pending Approvals',
                  'Claim Verification',
                  'Platform Audit Logs',
                ],
                enabled:
                    !_checkingPermissions &&
                    user != null &&
                    _canUseRole(user, 'admin'),
              ),
              const SizedBox(height: 32),

              // Continue Button
              SizedBox(
                height: 52,
                child: ElevatedButton(
                  key: const ValueKey('continue_role_btn'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                  onPressed: _checkingPermissions || _savingRole
                      ? null
                      : _applyRoleSelection,
                  child: Text(
                    _savingRole
                        ? 'Verifying access…'
                        : widget.isSwitching
                        ? 'Switch workspace'
                        : 'Continue to workspace',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRoleCard({
    required String roleId,
    required String title,
    required String subtitle,
    required String badgeText,
    required Color themeColor,
    required IconData icon,
    required List<String> features,
    required bool enabled,
  }) {
    final isSelected = _selectedRole == roleId;

    return Material(
      color: enabled && isSelected
          ? themeColor.withValues(alpha: 0.06)
          : Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        key: ValueKey('role_card_$roleId'),
        borderRadius: BorderRadius.circular(16),
        onTap: enabled
            ? () {
                setState(() => _selectedRole = roleId);
              }
            : null,
        child: Opacity(
          opacity: enabled ? 1 : 0.68,
          child: _buildRoleCardContent(
            roleId: roleId,
            title: title,
            subtitle: subtitle,
            badgeText: badgeText,
            themeColor: themeColor,
            icon: icon,
            features: features,
            enabled: enabled,
            isSelected: isSelected,
          ),
        ),
      ),
    );
  }

  Widget _buildRoleCardContent({
    required String roleId,
    required String title,
    required String subtitle,
    required String badgeText,
    required Color themeColor,
    required IconData icon,
    required List<String> features,
    required bool enabled,
    required bool isSelected,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: enabled && isSelected ? themeColor : AppTheme.border,
          width: enabled && isSelected ? 2.0 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: enabled && isSelected
                      ? themeColor.withValues(alpha: 0.15)
                      : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  icon,
                  color: enabled && isSelected
                      ? themeColor
                      : AppTheme.secondaryText,
                  size: 26,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.mainText,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: themeColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        badgeText,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: themeColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                enabled && isSelected
                    ? Icons.check_circle_rounded
                    : enabled
                    ? Icons.radio_button_unchecked
                    : Icons.lock_outline_rounded,
                color: enabled && isSelected ? themeColor : AppTheme.border,
                size: 24,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            subtitle,
            style: const TextStyle(
              fontSize: 13,
              color: AppTheme.secondaryText,
              height: 1.4,
            ),
          ),
          if (features.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: features.map((feature) {
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check, size: 12, color: themeColor),
                      const SizedBox(width: 4),
                      Text(
                        feature,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: AppTheme.secondaryText,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }
}
