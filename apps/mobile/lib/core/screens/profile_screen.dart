import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:geolocator/geolocator.dart';
import 'package:grepmind_mobile/core/notifications/notification_permission_card.dart';
import 'package:grepmind_mobile/core/models/business.dart';
import 'package:grepmind_mobile/core/models/customer_address.dart';
import 'package:grepmind_mobile/core/network/api_client.dart';
import 'package:grepmind_mobile/core/providers/app_provider.dart';
import 'package:grepmind_mobile/core/theme/app_theme.dart';
import 'package:grepmind_mobile/core/widgets/abashyaka_premium_header.dart';
import 'package:grepmind_mobile/core/widgets/fluid_wave_painter.dart';
import 'package:grepmind_mobile/core/widgets/premium_card.dart';
import 'package:grepmind_mobile/core/screens/merchant_workspace_screen.dart';
import 'package:grepmind_mobile/core/screens/merchant_registration_screen.dart';
import 'package:grepmind_mobile/core/screens/role_selection_screen.dart';
import 'package:grepmind_mobile/core/screens/admin_portal_screen.dart';
import 'package:grepmind_mobile/core/screens/order_history_screen.dart';
import 'package:grepmind_mobile/core/screens/saved_screen.dart';
import 'package:grepmind_mobile/core/screens/customer_addresses_screen.dart';
import 'package:grepmind_mobile/core/screens/rider_application_screen.dart';
import 'package:grepmind_mobile/core/screens/rider_workspace_screen.dart';
import 'package:grepmind_mobile/core/screens/rider_earnings_screen.dart';

/// User profile screen showing user info and settings.
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  bool _savingPhoto = false;
  String? _email;
  List<CustomerAddress> _addresses = const [];

  @override
  void initState() {
    super.initState();
    _loadProfileDetails();
  }

  Future<void> _loadProfileDetails() async {
    final user = ref.read(authProvider).user;
    if (user == null) return;
    try {
      final storedEmail = await const FlutterSecureStorage().read(
        key: 'user_email_${user.id}',
      );
      final response = await apiClient.get('/customer/addresses');
      final rows = response.data['data'] as List<dynamic>? ?? const [];
      final addrs = rows
          .map((e) => CustomerAddress.fromJson(e as Map<String, dynamic>))
          .toList();
      if (!mounted) return;
      setState(() {
        _email = storedEmail;
        _addresses = addrs;
      });
    } catch (_) {}
  }

  CustomerAddress? get _primaryAddress {
    if (_addresses.isEmpty) return null;
    return _addresses.firstWhere(
      (a) => a.isDefault,
      orElse: () => _addresses.first,
    );
  }

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
                style: TextStyle(
                  fontSize: 16,
                  color: AbashyakaColors.premiumObsidian,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final user = authState.user!;
    final activeRole = authState.activeRole ?? 'customer';
    final isCustomer = activeRole == 'customer';
    final profileCard = _buildProfileHeader(user, activeRole);

    return Scaffold(
      backgroundColor: AbashyakaColors.pearlWhite,
      appBar: AppBar(
        title: const Text('My Profile'),
        systemOverlayStyle: isCustomer ? SystemUiOverlayStyle.dark : null,
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => _showEditDialog(context, user),
            tooltip: 'Edit profile',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadProfileDetails,
        color: AbashyakaColors.signatureTeal,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (isCustomer)
                DecoratedBox(
                  decoration: const BoxDecoration(
                    color: AbashyakaColors.pearlWhite,
                    image: DecorationImage(
                      image: AssetImage(
                        'assets/backgrounds/premium/role_selection_background.webp',
                      ),
                      fit: BoxFit.cover,
                      alignment: Alignment.topCenter,
                      opacity: 0.45,
                    ),
                  ),
                  child: AbashyakaPremiumHeader(
                    variant: FluidWaveVariant.profile,
                    bottom: profileCard,
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(AbashyakaSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!isCustomer) ...[
                      profileCard,
                      const SizedBox(height: AbashyakaSpacing.lg),
                    ],
                    _buildProfileInfo(user, activeRole),
                    const SizedBox(height: AbashyakaSpacing.lg),
                    _buildAccountSection(context, activeRole, user),
                    const SizedBox(height: AbashyakaSpacing.lg),
                    _buildActions(context, ref, isCustomer: isCustomer),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProfileHeader(AppUser user, String activeRole) {
    final isMerchant = activeRole == 'merchant';
    final isRider = activeRole == 'rider';
    final photoUrl = user.avatarUrl == null || user.avatarUrl!.isEmpty
        ? null
        : apiClient.resolveMediaUrl(user.avatarUrl!);
    return PremiumCard(
      child: Column(
        children: [
          Row(
            children: [
              Stack(
                children: [
                  Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: AbashyakaGradients.metallicButton.colors,
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color:
                              (isRider
                                      ? AbashyakaColors.rider
                                      : (isMerchant
                                            ? AppTheme.coral
                                            : AbashyakaColors.signatureTeal))
                                  .withValues(alpha: 0.25),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: CircleAvatar(
                      radius: 36,
                      backgroundColor: AbashyakaColors.pureWhite,
                      child: CircleAvatar(
                        radius: 33,
                        backgroundColor: isRider
                            ? AbashyakaColors.riderSurface
                            : (isMerchant
                                  ? AbashyakaColors.merchantSurface
                                  : AbashyakaColors.iceAquaWhite),
                        backgroundImage: photoUrl == null
                            ? null
                            : CachedNetworkImageProvider(photoUrl),
                        child: photoUrl == null
                            ? Icon(
                                Icons.person_rounded,
                                size: 36,
                                color: isRider
                                    ? AbashyakaColors.rider
                                    : (isMerchant
                                          ? AppTheme.coral
                                          : AbashyakaColors.signatureTeal),
                              )
                            : null,
                      ),
                    ),
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: IconButton.filled(
                      key: const ValueKey('profile_photo_button'),
                      tooltip: 'Change profile photo',
                      onPressed: _savingPhoto ? null : _chooseProfilePhoto,
                      style: IconButton.styleFrom(
                        minimumSize: const Size.square(
                          AbashyakaSpacing.touchTargetMin,
                        ),
                        backgroundColor: isRider
                            ? AbashyakaColors.rider
                            : (isMerchant
                                  ? AppTheme.coral
                                  : AbashyakaColors.signatureTeal),
                        foregroundColor: AbashyakaColors.pureWhite,
                      ),
                      icon: _savingPhoto
                          ? const SizedBox.square(
                              dimension: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.camera_alt_outlined, size: 18),
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
                        color: AbashyakaColors.premiumObsidian,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Wrap(
                      spacing: AbashyakaSpacing.xs,
                      runSpacing: AbashyakaSpacing.xxs,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          user.phoneE164,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: AbashyakaColors.graphiteCharcoal,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AbashyakaColors.iceAquaWhite,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: AbashyakaColors.aquaSilverBorder,
                            ),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.check_circle_rounded,
                                size: 12,
                                color: AbashyakaColors.success,
                              ),
                              SizedBox(width: 3),
                              Text(
                                'Verified',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: AbashyakaColors.signatureTeal,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: AbashyakaSpacing.xs,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: isRider
                                ? AbashyakaColors.riderSurface
                                : (isMerchant
                                      ? AbashyakaColors.merchantSurface
                                      : AbashyakaColors.iceAquaWhite),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            activeRole.toUpperCase(),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: isRider
                                  ? AppTheme.riderAmberDeep
                                  : (isMerchant
                                        ? AppTheme.coral
                                        : AppTheme.emeraldDark),
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () => _showEditDialog(context, user),
                          style: TextButton.styleFrom(
                            minimumSize: const Size(
                              0,
                              AbashyakaSpacing.touchTargetMin,
                            ),
                            foregroundColor: isRider
                                ? AbashyakaColors.rider
                                : (isMerchant
                                      ? AppTheme.coral
                                      : AbashyakaColors.signatureTeal),
                          ),
                          icon: const Icon(Icons.edit_outlined, size: 16),
                          label: const Text('Edit Profile'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
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
    final isMerchant = activeRole == 'merchant';
    final isRider = activeRole == 'rider';
    final primaryAddr = _primaryAddress;
    return PremiumCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.badge_outlined,
                size: 20,
                color: isRider
                    ? AbashyakaColors.rider
                    : (isMerchant
                          ? AppTheme.coral
                          : AbashyakaColors.signatureTeal),
              ),
              const SizedBox(width: AbashyakaSpacing.xs),
              const Expanded(
                child: Text(
                  'Personal Details',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AbashyakaColors.premiumObsidian,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => _showEditDialog(context, user),
                style: TextButton.styleFrom(
                  minimumSize: const Size.square(
                    AbashyakaSpacing.touchTargetMin,
                  ),
                  foregroundColor: isRider
                      ? AbashyakaColors.rider
                      : (isMerchant
                            ? AppTheme.coral
                            : AbashyakaColors.signatureTeal),
                ),
                child: const Text('Edit'),
              ),
            ],
          ),
          const SizedBox(height: AbashyakaSpacing.xs),
          _buildDetailRow(
            icon: Icons.person_outline,
            label: 'Full Name',
            value: user.displayName?.trim().isNotEmpty == true
                ? user.displayName!
                : 'Add your name',
            isPlaceholder: user.displayName?.trim().isNotEmpty != true,
            isMerchant: isMerchant,
            isRider: isRider,
            onTap: () => _showEditDialog(context, user),
          ),
          const Divider(height: 20),
          _buildDetailRow(
            icon: Icons.phone_outlined,
            label: 'Mobile Phone',
            value: user.phoneE164,
            isMerchant: isMerchant,
            isRider: isRider,
            badge: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: isRider
                    ? AbashyakaColors.riderSurface
                    : (isMerchant
                          ? AbashyakaColors.merchantSurface
                          : AbashyakaColors.iceAquaWhite),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '✓ Verified',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: isRider
                      ? AbashyakaColors.rider
                      : (isMerchant
                            ? AppTheme.coral
                            : AbashyakaColors.signatureTeal),
                ),
              ),
            ),
          ),
          const Divider(height: 20),
          _buildDetailRow(
            icon: Icons.mail_outline_rounded,
            label: 'Email Address',
            value: (_email != null && _email!.isNotEmpty)
                ? _email!
                : 'Not added • Tap to add',
            isPlaceholder: _email == null || _email!.isEmpty,
            isMerchant: isMerchant,
            isRider: isRider,
            onTap: () => _showEditDialog(context, user),
          ),
          const Divider(height: 20),
          _buildDetailRow(
            icon: Icons.location_on_outlined,
            label: 'Primary Address',
            value: primaryAddr != null
                ? '${primaryAddr.label}: ${primaryAddr.formatted}'
                : 'No address saved • Tap to add',
            isPlaceholder: primaryAddr == null,
            isMerchant: isMerchant,
            isRider: isRider,
            onTap: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const CustomerAddressesScreen(),
                ),
              );
              _loadProfileDetails();
            },
          ),
          const Divider(height: 20),
          _buildDetailRow(
            icon: Icons.translate_rounded,
            label: 'Language',
            value: user.preferredLanguage == 'or' ? 'ଓଡ଼ିଆ (Odia)' : 'English',
            isMerchant: isMerchant,
            isRider: isRider,
            onTap: () => _showEditDialog(context, user),
          ),
          const Divider(height: 20),
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: isRider
                      ? AbashyakaColors.riderSurface
                      : (isMerchant
                            ? AbashyakaColors.merchantSurface
                            : AbashyakaColors.iceAquaWhite),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.tag_rounded,
                  color: isRider
                      ? AbashyakaColors.rider
                      : (isMerchant ? AppTheme.coral : AppTheme.emerald),
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Account ID',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: AbashyakaColors.graphiteCharcoal,
                      ),
                    ),
                    SizedBox(height: 2),
                  ],
                ),
              ),
              Flexible(
                child: Text(
                  _shortAccountId(user.id),
                  key: const ValueKey('short_account_id'),
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AbashyakaColors.premiumObsidian,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Copy account ID',
                icon: const Icon(Icons.copy_outlined, size: 16),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: user.id));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Account ID copied.')),
                  );
                },
              ),
            ],
          ),
          const Divider(height: 20),
          _buildDetailRow(
            icon: Icons.shield_outlined,
            label: 'Account Status',
            value: _formatStatus(user.status),
            isMerchant: isMerchant,
            isRider: isRider,
          ),
          if (user.roles.isNotEmpty) ...[
            const Divider(height: 20),
            _buildDetailRow(
              icon: Icons.admin_panel_settings_outlined,
              label: 'Assigned Roles',
              value: user.roles.join(', '),
              isMerchant: isMerchant,
              isRider: isRider,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDetailRow({
    required IconData icon,
    required String label,
    required String value,
    bool isPlaceholder = false,
    bool isMerchant = false,
    bool isRider = false,
    Widget? badge,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        constraints: const BoxConstraints(
          minHeight: AbashyakaSpacing.touchTargetMin,
        ),
        padding: const EdgeInsets.symmetric(vertical: AbashyakaSpacing.xxs),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: isRider
                    ? AbashyakaColors.riderSurface
                    : (isMerchant
                          ? AbashyakaColors.merchantSurface
                          : AbashyakaColors.iceAquaWhite),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                icon,
                color: isRider
                    ? AbashyakaColors.rider
                    : (isMerchant ? AppTheme.coral : AppTheme.emerald),
                size: 18,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: AbashyakaColors.graphiteCharcoal,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: isPlaceholder
                          ? FontWeight.w400
                          : FontWeight.w600,
                      color: isPlaceholder
                          ? AbashyakaColors.signatureTeal
                          : AbashyakaColors.premiumObsidian,
                    ),
                  ),
                  if (badge != null) ...[
                    const SizedBox(height: AbashyakaSpacing.xxs),
                    badge,
                  ],
                ],
              ),
            ),
            if (onTap != null) ...[
              const SizedBox(width: 8),
              const Icon(
                Icons.chevron_right,
                size: 18,
                color: AppTheme.hintText,
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _shortAccountId(String id) => id.length <= 16
      ? id
      : '${id.substring(0, 8)}…${id.substring(id.length - 6)}';

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

  Widget _buildAccountSection(
    BuildContext context,
    String activeRole,
    AppUser user,
  ) {
    final isMerchantRole = activeRole == 'merchant';
    final isAdminRole = activeRole == 'admin';
    final availableRoles = <String>[
      if (user.roles.contains('customer')) 'Customer',
      if (user.roles.contains('merchant') ||
          user.roles.contains('professional'))
        'Merchant',
      if (user.roles.contains('rider') && user.riderStatus == 'approved')
        'Rider',
      if (user.roles.contains('admin')) 'Admin',
    ];

    final isCustomer = activeRole == 'customer';
    final accountOptions = <Widget>[
      // Customer Orders & Bookings (Food Delivery, Tables, Stays)
      _buildAccountOption(
        icon: Icons.receipt_long_rounded,
        title: 'My Orders & Bookings',
        subtitle: 'Track active food deliveries, table reservations & stays',
        iconColor: AbashyakaColors.signatureTeal,
        iconBgColor: AbashyakaColors.iceAquaWhite,
        onTap: () => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const OrderHistoryScreen())),
      ),
      const Divider(),

      if (activeRole == 'customer') ...[
        _buildAccountOption(
          icon: Icons.pedal_bike_outlined,
          title: user.riderStatus == null
              ? 'Become a delivery partner'
              : 'Rider application',
          subtitle: user.riderStatus == null
              ? 'Apply to join the Abashyaka rider network'
              : 'Application status: ${user.riderStatus!.replaceAll('_', ' ')}',
          iconColor: AbashyakaColors.metallicTeal,
          iconBgColor: AbashyakaColors.iceAquaWhite,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const RiderApplicationScreen()),
          ),
        ),
        const Divider(),
        _buildAccountOption(
          icon: Icons.location_on_outlined,
          title: 'Saved addresses',
          subtitle: 'Manage delivery locations and contact details',
          iconColor: AbashyakaColors.information,
          iconBgColor: AbashyakaColors.pearlWhite,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const CustomerAddressesScreen()),
          ),
        ),
        const Divider(),
        _buildAccountOption(
          key: const ValueKey('profile_saved_businesses'),
          icon: Icons.favorite_border_rounded,
          title: 'Saved businesses',
          subtitle: 'Open your bookmarked shops and services',
          iconColor: AbashyakaColors.favourite,
          iconBgColor: AbashyakaColors.pearlWhite,
          onTap: () =>
              Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => const SavedScreen())),
        ),
        const Divider(),
      ],

      // Portal / Role Switcher Tile
      _buildAccountOption(
        icon: Icons.swap_horiz_rounded,
        title: 'Switch Portal / Experience',
        subtitle:
            'Current mode: ${activeRole.toUpperCase()} · Available: ${availableRoles.join(', ')}',
        iconColor: AbashyakaColors.warning,
        iconBgColor: AbashyakaColors.warningSurface,
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
          iconColor: AppTheme.coral,
          iconBgColor: AbashyakaColors.merchantSurface,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const MerchantWorkspaceScreen()),
          ),
        ),
        const Divider(),
      ],

      // Rider Workspace & Earnings - ONLY visible in Rider mode
      if (activeRole == 'rider') ...[
        _buildAccountOption(
          icon: Icons.delivery_dining_outlined,
          title: 'Rider Dashboard',
          subtitle: 'Active deliveries, dispatch & availability',
          iconColor: AbashyakaColors.rider,
          iconBgColor: AbashyakaColors.riderSurface,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const RiderDashboardScreen()),
          ),
        ),
        const Divider(),
        _buildAccountOption(
          icon: Icons.account_balance_wallet_outlined,
          title: 'Rider Earnings & COD Liability',
          subtitle: 'Delivery compensation, ledger summary & remittances',
          iconColor: AbashyakaColors.rider,
          iconBgColor: AbashyakaColors.riderSurface,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const RiderEarningsScreen()),
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
          iconColor: AbashyakaColors.admin,
          iconBgColor: AbashyakaColors.adminSurface,
          onTap: () => Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const AdminPortalScreen())),
        ),
        const Divider(),
      ],

      // Register or Claim Business (available to Customer & Merchant)
      _buildAccountOption(
        icon: Icons.add_business_outlined,
        title: 'Register / Claim Business',
        subtitle: 'List your shop or professional trade on Abashyaka',
        iconColor: isMerchantRole
            ? AppTheme.coral
            : AbashyakaColors.signatureTeal,
        iconBgColor: isMerchantRole
            ? AbashyakaColors.merchantSurface
            : AbashyakaColors.iceAquaWhite,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const MerchantRegistrationScreen()),
        ),
      ),
    ];
    final preferenceOptions = <Widget>[
      _buildAccountOption(
        icon: Icons.security,
        title: 'Sign-in & security',
        subtitle: 'Protected by 6-digit phone OTP',
        iconColor: AbashyakaColors.graphiteCharcoal,
        iconBgColor: AbashyakaColors.pearlWhite,
        onTap: () => _showSecurityDialog(context),
      ),
      const Divider(),
      _buildAccountOption(
        icon: Icons.notifications_outlined,
        title: 'Notification Settings',
        subtitle: 'Choose updates for your account',
        iconColor: AbashyakaColors.offer,
        iconBgColor: AbashyakaColors.offerSurface,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const NotificationSettingsScreen()),
        ),
      ),
      const Divider(),
      _buildAccountOption(
        icon: Icons.privacy_tip_outlined,
        title: 'Privacy & data',
        subtitle: 'How account and location data are used',
        iconColor: AbashyakaColors.signatureTeal,
        iconBgColor: AbashyakaColors.iceAquaWhite,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const PrivacySettingsScreen()),
        ),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSettingsCard(
          icon: Icons.widgets_outlined,
          title: isCustomer ? 'Account & Portals' : 'Account & Portal',
          options: [
            ...accountOptions,
            if (!isCustomer) ...[const Divider(), ...preferenceOptions],
          ],
        ),
        if (isCustomer) ...[
          const SizedBox(height: AbashyakaSpacing.lg),
          _buildSettingsCard(
            icon: Icons.shield_outlined,
            title: 'Security & Preferences',
            options: preferenceOptions,
          ),
        ],
      ],
    );
  }

  Widget _buildSettingsCard({
    required IconData icon,
    required String title,
    required List<Widget> options,
  }) {
    return PremiumCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: AbashyakaColors.signatureTeal),
              const SizedBox(width: AbashyakaSpacing.xs),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AbashyakaColors.premiumObsidian,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AbashyakaSpacing.xs),
          ...options,
        ],
      ),
    );
  }

  Widget _buildAccountOption({
    Key? key,
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    Color? iconColor,
    Color? iconBgColor,
  }) {
    final fg = iconColor ?? AppTheme.emerald;
    final bg = iconBgColor ?? AbashyakaColors.iceAquaWhite;
    return InkWell(
      key: key,
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: fg.withValues(alpha: 0.15)),
              ),
              child: Icon(icon, color: fg, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AbashyakaColors.premiumObsidian,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AbashyakaColors.graphiteCharcoal,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: AppTheme.hintText,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActions(
    BuildContext context,
    WidgetRef ref, {
    required bool isCustomer,
  }) {
    if (isCustomer) {
      final style = OutlinedButton.styleFrom(
        minimumSize: const Size(0, AbashyakaSpacing.touchTargetMin),
        foregroundColor: AbashyakaColors.error,
        backgroundColor: AbashyakaColors.pureWhite,
        side: const BorderSide(color: AbashyakaColors.error),
      );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OutlinedButton.icon(
            onPressed: () => _showLogoutDialog(context, ref),
            icon: const Icon(Icons.logout),
            label: const Text('Log out'),
            style: style,
          ),
          TextButton.icon(
            onPressed: () => _showDeleteAccountInfo(context),
            icon: const Icon(Icons.delete_outline),
            label: const Text('Delete account'),
            style: TextButton.styleFrom(
              minimumSize: const Size(0, AbashyakaSpacing.touchTargetMin),
              foregroundColor: AbashyakaColors.error,
            ),
          ),
        ],
      );
    }
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
    final activeRole = ref.read(authProvider).activeRole;
    final isMerchant = activeRole == 'merchant';
    final isRider = activeRole == 'rider';
    final nameController = TextEditingController(text: user.displayName ?? '');
    final emailController = TextEditingController(text: _email ?? '');
    var language = user.preferredLanguage;
    final formKey = GlobalKey<FormState>();

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: AbashyakaColors.pureWhite,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          final primaryAddr = _primaryAddress;
          return Padding(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 8,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
            ),
            child: SingleChildScrollView(
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(
                            Icons.arrow_back_rounded,
                            color: AbashyakaColors.premiumObsidian,
                          ),
                          tooltip: 'Back',
                          onPressed: () => Navigator.pop(ctx),
                        ),
                        const SizedBox(width: 4),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Edit Profile',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: AbashyakaColors.premiumObsidian,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Update your personal information',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AbashyakaColors.graphiteCharcoal,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.close,
                            color: AbashyakaColors.graphiteCharcoal,
                          ),
                          tooltip: 'Close',
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Full Name Field
                    TextFormField(
                      controller: nameController,
                      maxLength: 80,
                      textCapitalization: TextCapitalization.words,
                      decoration: InputDecoration(
                        labelText: 'Full Name',
                        hintText: 'Enter your full name',
                        prefixIcon: const Icon(
                          Icons.person_outline,
                          color: AbashyakaColors.signatureTeal,
                        ),
                        filled: true,
                        fillColor: AbashyakaColors.pearlWhite,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(
                            color: AbashyakaColors.aquaSilverBorder,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(
                            color: AbashyakaColors.signatureTeal,
                            width: 1.5,
                          ),
                        ),
                        counterText: '',
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Mobile Number Field (Read-only / Verified)
                    TextFormField(
                      initialValue: user.phoneE164,
                      readOnly: true,
                      enabled: false,
                      decoration: InputDecoration(
                        labelText: 'Mobile Number',
                        prefixIcon: const Icon(
                          Icons.phone_android_outlined,
                          color: AbashyakaColors.graphiteCharcoal,
                        ),
                        suffixIcon: const Padding(
                          padding: EdgeInsets.only(right: 12),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.lock_outline,
                                size: 16,
                                color: AppTheme.hintText,
                              ),
                              SizedBox(width: 4),
                              Text(
                                'Verified',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: AbashyakaColors.signatureTeal,
                                ),
                              ),
                            ],
                          ),
                        ),
                        helperText: 'Verified with SMS OTP. Mobile number cannot be changed directly.',
                        helperMaxLines: 2,
                        filled: true,
                        fillColor: AbashyakaColors.softGrey,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(
                            color: AbashyakaColors.aquaSilverBorder,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Email Field
                    TextFormField(
                      controller: emailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: InputDecoration(
                        labelText: 'Email Address',
                        hintText: 'name@example.com',
                        prefixIcon: const Icon(
                          Icons.email_outlined,
                          color: AbashyakaColors.signatureTeal,
                        ),
                        filled: true,
                        fillColor: AbashyakaColors.pearlWhite,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(
                            color: AbashyakaColors.aquaSilverBorder,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(
                            color: AbashyakaColors.signatureTeal,
                            width: 1.5,
                          ),
                        ),
                      ),
                      validator: (val) {
                        final trimmed = val?.trim() ?? '';
                        if (trimmed.isEmpty) return null;
                        final emailRegex = RegExp(
                          r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
                        );
                        if (!emailRegex.hasMatch(trimmed)) {
                          return 'Please enter a valid email address';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    // Primary Delivery Address Section Card
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AbashyakaColors.pearlWhite,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: AbashyakaColors.aquaSilverBorder,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.location_on_outlined,
                                    size: 18,
                                    color: isMerchant
                                        ? AppTheme.coral
                                        : AbashyakaColors.signatureTeal,
                                  ),
                                  const SizedBox(width: 6),
                                  const Text(
                                    'Delivery Address',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: AbashyakaColors.premiumObsidian,
                                    ),
                                  ),
                                ],
                              ),
                              TextButton(
                                onPressed: () async {
                                  await Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          const CustomerAddressesScreen(),
                                    ),
                                  );
                                  await _loadProfileDetails();
                                  setModalState(() {});
                                },
                                style: TextButton.styleFrom(
                                  padding: EdgeInsets.zero,
                                  minimumSize: const Size(50, 30),
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                                child: Text(
                                  primaryAddr != null ? 'Change' : '+ Add',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: isRider
                                        ? AbashyakaColors.rider
                                        : (isMerchant
                                              ? AppTheme.coral
                                              : AbashyakaColors.signatureTeal),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            primaryAddr != null
                                ? '${primaryAddr.label}: ${primaryAddr.formatted}'
                                : 'No delivery address saved yet.',
                            style: TextStyle(
                              fontSize: 13,
                              color: primaryAddr != null
                                  ? AppTheme.mainText
                                  : AppTheme.secondaryText,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Language Selection Dropdown
                    DropdownButtonFormField<String>(
                      initialValue: language,
                      decoration: InputDecoration(
                        labelText: 'Preferred Language',
                        prefixIcon: const Icon(
                          Icons.translate_rounded,
                          color: AbashyakaColors.signatureTeal,
                        ),
                        filled: true,
                        fillColor: AbashyakaColors.pearlWhite,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(
                            color: AbashyakaColors.aquaSilverBorder,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(
                            color: AbashyakaColors.signatureTeal,
                            width: 1.5,
                          ),
                        ),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'en', child: Text('English')),
                        DropdownMenuItem(
                          value: 'or',
                          child: Text('ଓଡ଼ିଆ (Odia)'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setModalState(() => language = value);
                        }
                      },
                    ),
                    const SizedBox(height: 24),

                    // Save / Cancel Buttons
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(ctx),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              side: const BorderSide(
                                color: AbashyakaColors.aquaSilverBorder,
                              ),
                            ),
                            child: const Text(
                              'CANCEL',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: AbashyakaColors.graphiteCharcoal,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: isRider
                                  ? AbashyakaColors.rider
                                  : (isMerchant
                                        ? AppTheme.coral
                                        : AbashyakaColors.signatureTeal),
                              foregroundColor: AbashyakaColors.pureWhite,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            onPressed: () async {
                              if (!formKey.currentState!.validate()) return;
                              final newName = nameController.text.trim();
                              final newEmail = emailController.text.trim();

                              final ok = await ref
                                  .read(authProvider.notifier)
                                  .updateProfile({
                                    'display_name': newName,
                                    'preferred_language': language,
                                  });

                              if (newEmail.isNotEmpty) {
                                await const FlutterSecureStorage().write(
                                  key: 'user_email_${user.id}',
                                  value: newEmail,
                                );
                              } else {
                                await const FlutterSecureStorage().delete(
                                  key: 'user_email_${user.id}',
                                );
                              }

                              await _loadProfileDetails();

                              if (!ctx.mounted) return;
                              Navigator.pop(ctx);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  backgroundColor: isRider
                                      ? AbashyakaColors.rider
                                      : (isMerchant
                                            ? AppTheme.coral
                                            : AbashyakaColors.signatureTeal),
                                  behavior: SnackBarBehavior.floating,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  content: Row(
                                    children: [
                                      const Icon(
                                        Icons.check_circle,
                                        color: AbashyakaColors.pureWhite,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          ok
                                              ? 'Profile details updated successfully.'
                                              : 'Email saved, but profile update failed. Please retry.',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                            child: const Text(
                              'SAVE CHANGES',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    ).then((_) async {
      await Future<void>.delayed(const Duration(milliseconds: 350));
      nameController.dispose();
      emailController.dispose();
    });
  }

  void _showSecurityDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.verified_user_outlined, color: AppTheme.emerald),
        title: const Text('Secure OTP sign-in'),
        content: const Text(
          'Abashyaka uses a one-time code sent to your verified phone number. This account has no password, so there is no password to change. Never share a verification code with anyone.',
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
          const NotificationPermissionCard(),
          const SizedBox(height: 16),
          const PremiumCard(
            padding: EdgeInsets.all(18),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.notifications_active_outlined,
                  color: AppTheme.emerald,
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
                        activeTrackColor: AppTheme.emerald,
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
              color: AppTheme.emerald,
            ),
            title: const Text('Location permission'),
            subtitle: const Text(
              'Review Abashyaka permissions in Android settings',
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
