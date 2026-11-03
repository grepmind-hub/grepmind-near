import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:geolocator/geolocator.dart';
import 'package:grepmind_mobile/core/models/business.dart';
import 'package:grepmind_mobile/core/network/api_client.dart';
import 'package:grepmind_mobile/core/providers/app_provider.dart';
import 'package:grepmind_mobile/core/theme/app_theme.dart';
import 'package:grepmind_mobile/core/widgets/premium_card.dart';
import 'package:grepmind_mobile/core/screens/merchant_workspace_screen.dart';
import 'package:grepmind_mobile/core/screens/merchant_registration_screen.dart';
import 'package:grepmind_mobile/core/screens/role_selection_screen.dart';
import 'package:grepmind_mobile/core/screens/admin_portal_screen.dart';
import 'package:grepmind_mobile/core/screens/order_history_screen.dart';

/// User profile screen showing user info and settings.
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  bool _savingPhoto = false;

  @override
  Widget build(BuildContext context) {
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
            onPressed: () => _showEditDialog(context, authState.user!),
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
            _buildProfileInfo(
              authState.user!,
              authState.activeRole ?? 'customer',
            ),
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
    final photoUrl = user.avatarUrl == null || user.avatarUrl!.isEmpty
        ? null
        : apiClient.resolveMediaUrl(user.avatarUrl!);
    return PremiumCard(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Stack(
            children: [
              CircleAvatar(
                radius: 38,
                backgroundColor: AppTheme.primaryContainer,
                backgroundImage: photoUrl == null
                    ? null
                    : CachedNetworkImageProvider(photoUrl),
                child: photoUrl == null
                    ? const Icon(
                        Icons.person_rounded,
                        size: 38,
                        color: AppTheme.primary,
                      )
                    : null,
              ),
              Positioned(
                right: 0,
                bottom: 0,
                child: Material(
                  color: AppTheme.primary,
                  shape: const CircleBorder(),
                  child: InkWell(
                    key: const ValueKey('profile_photo_button'),
                    customBorder: const CircleBorder(),
                    onTap: _savingPhoto ? null : _chooseProfilePhoto,
                    child: Padding(
                      padding: const EdgeInsets.all(7),
                      child: _savingPhoto
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(
                              Icons.camera_alt_outlined,
                              size: 16,
                              color: Colors.white,
                            ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user.displayName?.trim().isNotEmpty == true
                      ? user.displayName!
                      : _getDisplayName(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.mainText,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  user.phoneE164,
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppTheme.secondaryText,
                  ),
                ),
                const SizedBox(height: 9),
                TextButton.icon(
                  onPressed: () => _showEditDialog(context, user),
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  label: const Text('Edit profile'),
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(48, 36),
                    tapTargetSize: MaterialTapTargetSize.padded,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _chooseProfilePhoto() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Take a photo'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;
    try {
      final image = await ImagePicker().pickImage(
        source: source,
        maxWidth: 1200,
        maxHeight: 1200,
        imageQuality: 85,
      );
      if (image == null) return;
      setState(() => _savingPhoto = true);
      final Uint8List bytes = await image.readAsBytes();
      final upload = await apiClient.uploadMedia(
        bytes: bytes,
        filename: image.name,
        purpose: 'avatar',
      );
      final url = upload['url'] as String?;
      final ok =
          url != null &&
          await ref.read(authProvider.notifier).updateProfile({
            'avatar_url': url,
          });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ok ? 'Profile photo updated.' : 'Photo uploaded, but the profile could not be updated. Please retry.',
          ),
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not update the profile photo. Check your connection and try again.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _savingPhoto = false);
    }
  }

  Widget _buildProfileInfo(AppUser user, String activeRole) {
    return PremiumCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Account ID',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.secondaryText,
                  ),
                ),
              ),
              Flexible(
                child: Text(
                  _shortAccountId(user.id),
                  key: const ValueKey('short_account_id'),
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppTheme.mainText,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Copy account ID',
                icon: const Icon(Icons.copy_outlined, size: 18),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: user.id));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Account ID copied.')),
                  );
                },
              ),
            ],
          ),
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

  String _shortAccountId(String id) => id.length <= 16
      ? id
      : '${id.substring(0, 8)}…${id.substring(id.length - 6)}';

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

  String _getDisplayName() {
    return 'Add your name';
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
            subtitle:
                'Track active food deliveries, table reservations & stays',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const OrderHistoryScreen()),
            ),
          ),
          const Divider(),

          // Portal / Role Switcher Tile
          _buildAccountOption(
            icon: Icons.swap_horiz_rounded,
            title: 'Switch Portal / Experience',
            subtitle:
                'Current mode: ${activeRole.toUpperCase()} (Customer, Merchant, Admin)',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const RoleSelectionScreen(isSwitching: true),
              ),
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
                MaterialPageRoute(
                  builder: (_) => const MerchantWorkspaceScreen(),
                ),
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
              MaterialPageRoute(
                builder: (_) => const MerchantRegistrationScreen(),
              ),
            ),
          ),
          const Divider(),

          _buildAccountOption(
            icon: Icons.security,
            title: 'Sign-in & security',
            subtitle: 'Passwordless sign-in with a one-time code',
            onTap: () => _showSecurityDialog(context),
          ),
          const Divider(),
          _buildAccountOption(
            icon: Icons.notifications_outlined,
            title: 'Notification Settings',
            subtitle: 'Choose updates for your account',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const NotificationSettingsScreen(),
              ),
            ),
          ),
          const Divider(),
          _buildAccountOption(
            icon: Icons.privacy_tip_outlined,
            title: 'Privacy & data',
            subtitle: 'How account and location data are used',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const PrivacySettingsScreen()),
            ),
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
            onPressed: () => _showDeleteAccountInfo(context),
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

  void _showEditDialog(BuildContext context, AppUser user) {
    final nameController = TextEditingController(text: user.displayName ?? '');
    var language = user.preferredLanguage;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Edit profile'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                maxLength: 80,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Display name',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: language,
                decoration: const InputDecoration(
                  labelText: 'Preferred language',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'en', child: Text('English')),
                  DropdownMenuItem(value: 'or', child: Text('ଓଡ଼ିଆ')),
                ],
                onChanged: (value) {
                  if (value != null) setDialogState(() => language = value);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('CANCEL'),
            ),
            FilledButton(
              onPressed: () async {
                final ok = await ref.read(authProvider.notifier).updateProfile({
                  'display_name': nameController.text.trim(),
                  'preferred_language': language,
                });
                if (!ctx.mounted) return;
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      ok
                          ? 'Profile updated.'
                          : 'Could not save your profile. Please retry.',
                    ),
                  ),
                );
              },
              child: const Text('SAVE'),
            ),
          ],
        ),
      ),
    ).then((_) async {
      // The dialog route completes before its reverse transition removes the
      // TextField. Dispose only after the transition so the controller has no
      // remaining EditableText dependents.
      await Future<void>.delayed(const Duration(milliseconds: 350));
      nameController.dispose();
    });
  }

  void _showSecurityDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.verified_user_outlined, color: AppTheme.primary),
        title: const Text('Secure OTP sign-in'),
        content: const Text(
          'Grepmind Near uses a one-time code sent to your verified phone number. This account has no password, so there is no password to change. Never share a verification code with anyone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('GOT IT'),
          ),
        ],
      ),
    );
  }

  void _showDeleteAccountInfo(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.info_outline, color: AppTheme.warning),
        title: const Text('Account deletion'),
        content: const Text(
          'Self-service account deletion is not available yet. Your account and activity will not be changed from this screen.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('CLOSE'),
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

class NotificationSettingsScreen extends ConsumerWidget {
  const NotificationSettingsScreen({super.key});

  static const _labels = <String, (String, String)>{
    'booking_updates': (
      'Bookings and orders',
      'Confirmations and status changes',
    ),
    'service_updates': ('Service requests', 'Replies and progress updates'),
    'offers': ('Local offers', 'Offers from businesses you follow or browse'),
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).user;
    final preferences = user?.notificationPreferences ?? const <String, bool>{};
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: const Text('Notification settings')),
      body: ListView(
        padding: const EdgeInsets.all(kScreenPadding),
        children: [
          const PremiumCard(
            padding: EdgeInsets.all(18),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.notifications_active_outlined,
                  color: AppTheme.primary,
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'These preferences are saved to your account. Mobile push delivery is not enabled yet; they will be honored when delivery is available.',
                    style: TextStyle(
                      color: AppTheme.secondaryText,
                      height: 1.45,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          PremiumCard(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Column(
              children: _labels.entries
                  .map(
                    (entry) => Material(
                      color: AppTheme.surface,
                      child: SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        value: preferences[entry.key] ?? true,
                        title: Text(
                          entry.value.$1,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(entry.value.$2),
                        activeTrackColor: AppTheme.primary,
                        onChanged: (enabled) async {
                          final updated = {...preferences, entry.key: enabled};
                          final ok = await ref
                              .read(authProvider.notifier)
                              .updateProfile({
                                'notification_preferences': updated,
                              });
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  ok ? 'Preference saved.' : 'Could not save preference. Please retry.',
                                ),
                              ),
                            );
                          }
                        },
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class PrivacySettingsScreen extends StatelessWidget {
  const PrivacySettingsScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppTheme.background,
    appBar: AppBar(title: const Text('Privacy & data')),
    body: ListView(
      padding: const EdgeInsets.all(kScreenPadding),
      children: [
        const PremiumCard(
          padding: EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Your account information',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.mainText,
                ),
              ),
              SizedBox(height: 10),
              Text(
                'Your phone number and profile details are tied to your signed-in account. Your location is used to find nearby businesses when you grant location access. You can also choose a city manually.',
                style: TextStyle(color: AppTheme.secondaryText, height: 1.5),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Material(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(16),
          child: ListTile(
            leading: const Icon(
              Icons.location_on_outlined,
              color: AppTheme.primary,
            ),
            title: const Text('Location permission'),
            subtitle: const Text(
              'Review Grepmind Near permissions in Android settings',
            ),
            trailing: const Icon(Icons.open_in_new, size: 18),
            onTap: () async {
              final opened = await Geolocator.openAppSettings();
              if (!opened && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Open Android Settings to review app permissions.',
                    ),
                  ),
                );
              }
            },
          ),
        ),
        const SizedBox(height: 12),
        const PremiumCard(
          padding: EdgeInsets.all(18),
          child: Text(
            'Self-service account deletion is not available yet. This screen does not change or delete your account. The published privacy notice should provide the account deletion process before public launch.',
            style: TextStyle(color: AppTheme.secondaryText, height: 1.5),
          ),
        ),
      ],
    ),
  );
}
