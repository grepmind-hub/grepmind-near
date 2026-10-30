import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grepmind_mobile/core/models/business.dart';
import 'package:grepmind_mobile/core/providers/app_provider.dart';
import 'package:grepmind_mobile/core/theme/app_theme.dart';
import 'package:grepmind_mobile/core/widgets/premium_card.dart';
import 'package:grepmind_mobile/core/screens/merchant_workspace_screen.dart';
import 'package:grepmind_mobile/core/screens/merchant_registration_screen.dart';
import 'package:grepmind_mobile/core/screens/role_selection_screen.dart';
import 'package:grepmind_mobile/core/screens/admin_portal_screen.dart';
import 'package:grepmind_mobile/core/screens/order_history_screen.dart';

/// User profile screen showing user info and settings.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);

    if (authState.isLoading) {
      return const Scaffold(
        backgroundColor: AppTheme.background,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (!authState.isAuthenticated) {
      // Should be redirected to onboarding, but show error for now
      return const Scaffold(
        backgroundColor: AppTheme.background,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.person_outline, size: 64, color: AppTheme.hintText),
              SizedBox(height: 16),
              Text(
                'Please sign in to view your profile',
                style: TextStyle(fontSize: 16, color: AppTheme.mainText),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('My Profile'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => _showEditDialog(context),
            tooltip: 'Edit profile',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(kScreenPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildProfileHeader(authState.user!),
            const SizedBox(height: 24),
            _buildProfileInfo(authState.user!, authState.activeRole ?? 'customer'),
            const SizedBox(height: 24),
            _buildAccountSection(context, authState.activeRole ?? 'customer'),
            const SizedBox(height: 24),
            _buildActions(context, ref),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileHeader(AppUser user) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: AppTheme.primaryContainer,
              borderRadius: BorderRadius.circular(50),
            ),
            child: const Icon(Icons.person, size: 50, color: AppTheme.primary),
          ),
          const SizedBox(height: 16),
          Text(
            user.displayName ?? _getDisplayName(user.phoneE164),
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: AppTheme.mainText,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            user.phoneE164,
            style: const TextStyle(
              fontSize: 14,
              color: AppTheme.secondaryText,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileInfo(AppUser user, String activeRole) {
    return PremiumCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildInfoRow('Account ID', user.id),
          const Divider(),
          _buildInfoRow('Phone', user.phoneE164),
          const Divider(),
          _buildInfoRow('Active Mode', activeRole.toUpperCase()),
          const Divider(),
          _buildInfoRow('Status', _formatStatus(user.status)),
          const Divider(),
          _buildInfoRow('Language', user.preferredLanguage),
          if (user.roles.isNotEmpty) ...[
            const Divider(),
            _buildInfoRow('Assigned Roles', user.roles.join(', ')),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppTheme.secondaryText,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 14,
                color: AppTheme.mainText,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatStatus(String status) {
    switch (status) {
      case 'active':
        return 'Active';
      case 'suspended':
        return 'Suspended';
      case 'deleted':
        return 'Deleted';
      default:
        return status;
    }
  }

  String _getDisplayName(String phone) {
    // Extract last 4 digits for display
    final last4 = phone.length > 4 ? phone.substring(phone.length - 4) : phone;
    return 'User -$last4';
  }

  Widget _buildAccountSection(BuildContext context, String activeRole) {
    final isMerchantRole = activeRole == 'merchant';
    final isAdminRole = activeRole == 'admin';

    return PremiumCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Account & Portal',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppTheme.mainText,
            ),
          ),
          const SizedBox(height: 16),

          // Customer Orders & Bookings (Food Delivery, Tables, Stays)
          _buildAccountOption(
            icon: Icons.receipt_long_rounded,
            title: 'My Orders & Bookings',
            subtitle: 'Track active food deliveries, table reservations & stays',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const OrderHistoryScreen()),
            ),
          ),
          const Divider(),

          // Portal / Role Switcher Tile
          _buildAccountOption(
            icon: Icons.swap_horiz_rounded,
            title: 'Switch Portal / Experience',
            subtitle: 'Current mode: ${activeRole.toUpperCase()} (Customer, Merchant, Admin)',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const RoleSelectionScreen(isSwitching: true)),
            ),
          ),
          const Divider(),

          // Merchant Workspace - ONLY visible in Merchant mode
          if (isMerchantRole) ...[
            _buildAccountOption(
              icon: Icons.storefront_outlined,
              title: 'Merchant Workspace',
              subtitle: 'Manage your storefront, requests & catalog',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const MerchantWorkspaceScreen()),
              ),
            ),
            const Divider(),
          ],

          // Admin Portal - ONLY visible in Admin mode
          if (isAdminRole) ...[
            _buildAccountOption(
              icon: Icons.admin_panel_settings_outlined,
              title: 'Admin Moderation Portal',
              subtitle: 'Review listings, claims & platform audit logs',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AdminPortalScreen()),
              ),
            ),
            const Divider(),
          ],

          // Register or Claim Business (available to Customer & Merchant)
          _buildAccountOption(
            icon: Icons.add_business_outlined,
            title: 'Register / Claim Business',
            subtitle: 'List your shop or professional trade on Grepmind',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const MerchantRegistrationScreen()),
            ),
          ),
          const Divider(),

          _buildAccountOption(
            icon: Icons.security,
            title: 'Change Password',
            subtitle: 'Update your account password',
            onTap: () => _showComingSoonDialog(context, 'Password change'),
          ),
          const Divider(),
          _buildAccountOption(
            icon: Icons.notifications_outlined,
            title: 'Notification Settings',
            subtitle: 'Manage push notifications',
            onTap: () => _showComingSoonDialog(context, 'Notification settings'),
          ),
          const Divider(),
          _buildAccountOption(
            icon: Icons.privacy_tip_outlined,
            title: 'Privacy Settings',
            subtitle: 'Control your privacy preferences',
            onTap: () => _showComingSoonDialog(context, 'Privacy settings'),
          ),
        ],
      ),
    );
  }

  Widget _buildAccountOption({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppTheme.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: AppTheme.primary, size: 20),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.mainText,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.secondaryText,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppTheme.hintText, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildActions(BuildContext context, WidgetRef ref) {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: () => _showLogoutDialog(context, ref),
            icon: const Icon(Icons.logout),
            label: const Text('Log out'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.errorContainer,
              foregroundColor: AppTheme.error,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: () => _showComingSoonDialog(context, 'Delete account'),
            icon: const Icon(Icons.delete_outline),
            label: const Text('Delete account'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.transparent,
              foregroundColor: AppTheme.error,
              side: const BorderSide(color: AppTheme.error),
            ),
          ),
        ),
      ],
    );
  }

  void _showComingSoonDialog(BuildContext context, String feature) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('$feature (Coming Soon)'),
        content: const Text('This feature is currently under development.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showEditDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Profile'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              decoration: InputDecoration(
                labelText: 'Display Name',
                border: OutlineInputBorder(),
              ),
            ),
            SizedBox(height: 16),
            TextField(
              decoration: InputDecoration(
                labelText: 'Language',
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.words,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('CANCEL'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('SAVE'),
          ),
        ],
      ),
    );
  }

  void _showLogoutDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Log out'),
        content: const Text('Are you sure you want to log out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCEL'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              ref.read(authProvider.notifier).logout();
            },
            style: FilledButton.styleFrom(backgroundColor: AppTheme.error),
            child: const Text('LOG OUT'),
          ),
        ],
      ),
    );
  }
}