import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grepmind_mobile/core/providers/app_provider.dart';
import 'package:grepmind_mobile/core/screens/merchant_catalog_screen.dart';
import 'package:grepmind_mobile/core/screens/merchant_hours_coverage_screen.dart';
import 'package:grepmind_mobile/core/screens/merchant_registration_screen.dart';
import 'package:grepmind_mobile/core/theme/app_theme.dart';
import 'package:grepmind_mobile/core/widgets/screen_illustration_card.dart';
import 'package:grepmind_mobile/core/widgets/premium_card.dart';

/// Merchant Workspace Screen - Main dashboard for business owners.
/// Shows business profile, service requests, and management tools.
class MerchantWorkspaceScreen extends ConsumerStatefulWidget {
  const MerchantWorkspaceScreen({super.key});

  @override
  ConsumerState<MerchantWorkspaceScreen> createState() =>
      _MerchantWorkspaceScreenState();
}

class _MerchantWorkspaceScreenState
    extends ConsumerState<MerchantWorkspaceScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(merchantProvider.notifier).loadRequests();
      ref.read(merchantProfileProvider('').notifier).load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final merchantState = ref.watch(merchantProvider);
    final profileState = ref.watch(merchantProfileProvider(''));

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(
          title: const Text('Merchant Workspace'),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.dashboard_outlined), text: 'Dashboard'),
              Tab(icon: Icon(Icons.request_quote_outlined), text: 'Requests'),
              Tab(icon: Icon(Icons.store_outlined), text: 'Profile'),
            ],
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh_outlined),
              onPressed: () {
                ref.read(merchantProvider.notifier).loadRequests();
              },
              tooltip: 'Refresh',
            ),
          ],
        ),
        body: TabBarView(
          children: [
            _buildDashboardTab(merchantState),
            _buildRequestsTab(merchantState),
            _buildProfileTab(profileState),
          ],
        ),
      ),
    );
  }

  Widget _buildDashboardTab(MerchantRequestState state) {
    if (state.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.error != null) {
      return _buildErrorState(
        state.error!,
        () => ref.read(merchantProvider.notifier).loadRequests(),
      );
    }

    final pendingCount = state.items
        .where((r) => r.status == 'requested')
        .length;
    final acceptedCount = state.items
        .where((r) => r.status == 'accepted')
        .length;
    final completedCount = state.items
        .where((r) => r.status == 'completed')
        .length;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(kScreenPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ScreenIllustrationCard(
            illustration: ScreenIllustration.merchant,
            title: 'Your business workspace',
            subtitle: 'Manage your storefront and service requests',
            icon: Icons.storefront_outlined,
          ),
          const SizedBox(height: 14),
          // Welcome header
          PremiumCard(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: AppTheme.primaryContainer,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(
                    Icons.store_outlined,
                    color: AppTheme.primary,
                    size: 32,
                  ),
                ),
                const SizedBox(width: 16),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Welcome, Merchant',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.mainText,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Manage your business and service requests',
                        style: TextStyle(
                          fontSize: 14,
                          color: AppTheme.secondaryText,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Stats row
          Row(
            children: [
              Expanded(
                child: _statCard(
                  'Pending',
                  pendingCount.toString(),
                  AppTheme.warning,
                  AppTheme.warningContainer,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _statCard(
                  'Accepted',
                  acceptedCount.toString(),
                  AppTheme.success,
                  AppTheme.successContainer,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _statCard(
                  'Completed',
                  completedCount.toString(),
                  AppTheme.primary,
                  AppTheme.primaryContainer,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Quick actions
          _sectionTitle('Quick Actions'),
          Row(
            children: [
              Expanded(
                child: _actionButton(
                  Icons.request_quote,
                  'View Requests',
                  AppTheme.primary,
                  () => DefaultTabController.of(context).animateTo(1),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _actionButton(
                  Icons.edit_outlined,
                  'Edit Profile',
                  AppTheme.secondary,
                  () => DefaultTabController.of(context).animateTo(2),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _actionButton(
                  Icons.inventory_2_outlined,
                  'Manage Catalog',
                  const Color(0xFF0F766E),
                  () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const MerchantCatalogScreen(),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _actionButton(
                  Icons.add_circle_outline,
                  '+ Add Item',
                  const Color(0xFF2457D6),
                  () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const MerchantCatalogScreen(),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _actionButton(
                  Icons.schedule,
                  'Hours & Coverage',
                  const Color(0xFFD97706),
                  () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const MerchantHoursCoverageScreen(),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _actionButton(
                  Icons.radar,
                  'Service Radius',
                  const Color(0xFF7C3AED),
                  () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const MerchantHoursCoverageScreen(),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Recent requests preview
          if (state.items.isNotEmpty) ...[
            _sectionTitle('Recent Requests'),
            ...state.items.take(3).map((r) => _requestItem(r)),
          ] else ...[
            const SizedBox(height: 20),
            const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.inbox_outlined,
                    size: 48,
                    color: AppTheme.hintText,
                  ),
                  SizedBox(height: 16),
                  Text(
                    'No service requests yet',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.mainText,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Customers will send service requests here',
                    style: TextStyle(
                      fontSize: 14,
                      color: AppTheme.secondaryText,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRequestsTab(MerchantRequestState state) {
    if (state.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.error != null) {
      return _buildErrorState(
        state.error!,
        () => ref.read(merchantProvider.notifier).loadRequests(),
      );
    }

    return RefreshIndicator(
      onRefresh: () => ref.read(merchantProvider.notifier).loadRequests(),
      child: state.items.isEmpty
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.inbox_outlined,
                    size: 64,
                    color: AppTheme.hintText,
                  ),
                  SizedBox(height: 16),
                  Text(
                    'No service requests',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.mainText,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Customers will send service requests here',
                    style: TextStyle(color: AppTheme.secondaryText),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(kScreenPadding),
              itemCount: state.items.length,
              itemBuilder: (_, i) {
                final r = state.items[i];
                return _requestCard(r);
              },
            ),
    );
  }

  Widget _buildProfileTab(MerchantProfileState state) {
    if (state.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.error != null) {
      return _buildErrorState(
        state.error!,
        () => ref.read(merchantProfileProvider('').notifier).load(),
      );
    }

    final profile = state.profile ?? {};

    return SingleChildScrollView(
      padding: const EdgeInsets.all(kScreenPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Profile header
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(45),
                  child: SizedBox(
                    width: 90,
                    height: 90,
                    child: _extractString(profile['cover_photo_url']).isNotEmpty
                        ? Image.network(
                            _extractString(profile['cover_photo_url']),
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) =>
                                const _MerchantProfilePlaceholder(),
                          )
                        : const _MerchantProfilePlaceholder(),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  _extractString(profile['name']).isEmpty
                      ? 'My Business'
                      : _extractString(profile['name']),
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.mainText,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _extractString(profile['category_slug']).isEmpty
                      ? 'Business'
                      : _extractString(profile['category_slug']),
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppTheme.secondaryText,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Profile info
          _sectionTitle('Business Information'),
          PremiumCard(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _profileRow('Business Name', _extractString(profile['name'])),
                const Divider(),
                _profileRow(
                  'Description',
                  _extractString(profile['description']),
                ),
                const Divider(),
                _profileRow(
                  'Address',
                  '${_extractString(profile['address_text'])}, ${_extractString(profile['city'])}',
                ),
                const Divider(),
                _profileRow('Phone', _extractString(profile['phone_e164'])),
                const Divider(),
                _profileRow('Status', _extractString(profile['status'])),
                const Divider(),
                _profileRow(
                  'Verification',
                  _extractString(profile['verification_status']),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Actions
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: () => _showEditProfileDialog(),
              child: const Text('Edit Business Profile'),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.schedule),
              label: const Text('Operating Hours & Service Coverage'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.primary,
                side: const BorderSide(color: AppTheme.primary, width: 1.5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const MerchantHoursCoverageScreen(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statCard(
    String label,
    String value,
    Color color,
    Color containerColor,
  ) {
    return PremiumCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: containerColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              label == 'Pending'
                  ? Icons.pending
                  : label == 'Accepted'
                  ? Icons.check_circle
                  : Icons.check,
              color: color,
              size: 24,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: AppTheme.mainText,
            ),
          ),
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: AppTheme.secondaryText),
          ),
        ],
      ),
    );
  }

  Widget _actionButton(
    IconData icon,
    String label,
    Color color,
    VoidCallback onTap,
  ) {
    return Material(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Icon(icon, color: color, size: 32),
              const SizedBox(height: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 20, 0, 12),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: AppTheme.mainText,
        ),
      ),
    );
  }

  Widget _requestItem(MerchantServiceRequest r) {
    return PremiumCard(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          const CircleAvatar(
            radius: 20,
            backgroundColor: AppTheme.primaryContainer,
            child: Icon(
              Icons.person_outlined,
              color: AppTheme.primary,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  r.customerName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppTheme.mainText,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  r.description,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppTheme.secondaryText,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: _statusColor(r.status).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              r.status,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: _statusColor(r.status),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _requestCard(MerchantServiceRequest r) {
    return PremiumCard(
      margin: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                r.customerName,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppTheme.mainText,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _statusColor(r.status).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  r.status.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: _statusColor(r.status),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (r.serviceName != null)
            Text(
              'Service: ${r.serviceName}',
              style: const TextStyle(
                fontSize: 13,
                color: AppTheme.secondaryText,
              ),
            ),
          const SizedBox(height: 4),
          Text(
            r.description,
            style: const TextStyle(fontSize: 14, color: AppTheme.mainText),
          ),
          const SizedBox(height: 8),
          if (r.requestedFor != null)
            Text(
              'Requested for: ${r.requestedFor}',
              style: const TextStyle(
                fontSize: 12,
                color: AppTheme.secondaryText,
              ),
            ),
          const SizedBox(height: 16),
          Row(
            children: [
              if (r.status == 'requested') ...[
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _updateRequest(r.id, 'accepted'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.success,
                      side: const BorderSide(color: AppTheme.success),
                    ),
                    child: const Text('Accept'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _updateRequest(r.id, 'declined'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.error,
                      side: const BorderSide(color: AppTheme.error),
                    ),
                    child: const Text('Decline'),
                  ),
                ),
              ] else
                Expanded(
                  child: Text(
                    'Status: ${r.status}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.secondaryText,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'requested':
        return AppTheme.warning;
      case 'accepted':
        return AppTheme.success;
      case 'completed':
        return AppTheme.primary;
      case 'declined':
        return AppTheme.error;
      case 'cancelled':
        return AppTheme.hintText;
      default:
        return AppTheme.secondary;
    }
  }

  Future<void> _updateRequest(String requestId, String status) async {
    final success = await ref
        .read(merchantProvider.notifier)
        .updateRequestStatus(requestId, status);
    if (!success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to update request status')),
      );
    }
  }

  void _showEditProfileDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Profile'),
        content: const Text('Profile editing coming soon.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  String _extractString(dynamic val) {
    if (val == null) return '';
    if (val is String) return val;
    if (val is Map) {
      if (val.containsKey('String') && val['String'] != null) {
        return val['String'].toString();
      }
      return val.values.isNotEmpty ? val.values.first?.toString() ?? '' : '';
    }
    return val.toString();
  }

  Widget _profileRow(String label, dynamic value) {
    final displayValue = _extractString(value);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                color: AppTheme.secondaryText,
              ),
            ),
          ),
          Expanded(
            child: Text(
              displayValue,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: AppTheme.mainText,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(String error, VoidCallback onRetry) {
    final isAuthError =
        error.contains('401') ||
        error.toLowerCase().contains('unauthorized') ||
        error.contains('INVALID_TOKEN');
    final isNotFound =
        error.contains('404') ||
        error.contains('NOT_FOUND') ||
        error.contains('Business profile not found') ||
        error.contains('FORBIDDEN') ||
        error.contains('Merchant role required');

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: isAuthError
                    ? AppTheme.warningContainer
                    : (isNotFound
                          ? AppTheme.primaryContainer
                          : Colors.red.shade50),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isAuthError
                    ? Icons.lock_clock_outlined
                    : (isNotFound
                          ? Icons.storefront_outlined
                          : Icons.error_outline),
                size: 36,
                color: isAuthError
                    ? AppTheme.warning
                    : (isNotFound ? AppTheme.primary : AppTheme.error),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              isAuthError
                  ? 'Session Expired'
                  : (isNotFound
                        ? 'Business Profile Required'
                        : 'Unable to Load Workspace'),
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppTheme.mainText,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              isAuthError
                  ? 'Your login session has expired. Please sign in again with your registered phone number.'
                  : (isNotFound
                        ? 'You have not registered or claimed a business listing yet. Register your business to start receiving customer service requests and managing catalog.'
                        : 'We encountered an error while loading your merchant profile. Please check your network and try again.'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                color: AppTheme.secondaryText,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 20),
            if (isNotFound)
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const MerchantRegistrationScreen(),
                    ),
                  );
                },
                icon: const Icon(Icons.add_business_outlined, size: 20),
                label: const Text('Register Business'),
              )
            else if (isAuthError)
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () {
                  ref.read(authProvider.notifier).logout();
                },
                icon: const Icon(Icons.login_outlined, size: 20),
                label: const Text('Sign In Again'),
              )
            else
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: onRetry,
                icon: const Icon(Icons.refresh, size: 20),
                label: const Text('Try Again'),
              ),
          ],
        ),
      ),
    );
  }
}

class _MerchantProfilePlaceholder extends StatelessWidget {
  const _MerchantProfilePlaceholder();

  @override
  Widget build(BuildContext context) => Container(
    color: AppTheme.primaryContainer,
    alignment: Alignment.center,
    child: const Icon(Icons.store, color: AppTheme.primary, size: 40),
  );
}
