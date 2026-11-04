import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:grepmind_mobile/core/network/api_client.dart';
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
    extends ConsumerState<MerchantWorkspaceScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(merchantProvider.notifier).loadRequests();
      ref.read(merchantProfileProvider('').notifier).load();
      ref.read(merchantAnalyticsProvider.notifier).load();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final merchantState = ref.watch(merchantProvider);
    final profileState = ref.watch(merchantProfileProvider(''));
    final analyticsState = ref.watch(merchantAnalyticsProvider);

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Merchant Workspace'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
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
              ref.read(merchantProfileProvider('').notifier).load();
              ref.read(merchantAnalyticsProvider.notifier).load();
            },
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildDashboardTab(merchantState, analyticsState),
          _buildRequestsTab(merchantState),
          _buildProfileTab(profileState),
        ],
      ),
    );
  }

  Widget _buildDashboardTab(
    MerchantRequestState state,
    MerchantAnalyticsState analytics,
  ) {
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

          _sectionTitle('Customer views · Last 30 days'),
          Row(
            children: [
              Expanded(
                child: _viewMetricCard(
                  title: 'Business profile',
                  value: analytics.isLoading
                      ? null
                      : analytics.error == null
                      ? analytics.profileViews30d
                      : null,
                  icon: Icons.storefront_outlined,
                  color: AppTheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _viewMetricCard(
                  title: 'Product catalog',
                  value: analytics.isLoading
                      ? null
                      : analytics.error == null
                      ? analytics.productCatalogViews30d
                      : null,
                  icon: Icons.inventory_2_outlined,
                  color: AppTheme.secondary,
                ),
              ),
            ],
          ),
          if (analytics.error != null) ...[
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () =>
                  ref.read(merchantAnalyticsProvider.notifier).load(),
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Views unavailable · Retry'),
            ),
          ] else ...[
            const SizedBox(height: 8),
            const Text(
              'Unique signed-in customer views. Repeat visits count once per day.',
              style: TextStyle(fontSize: 12, color: AppTheme.secondaryText),
            ),
          ],
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
                  () => _tabController.animateTo(1),
                  key: const Key('merchant_view_requests'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _actionButton(
                  Icons.edit_outlined,
                  'Edit Profile',
                  AppTheme.secondary,
                  () => _tabController.animateTo(2),
                  key: const Key('merchant_edit_profile'),
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
    final canEditProfile = profile['can_edit_profile'] != false;
    final address = [
      _extractString(profile['address_text']),
      _extractString(profile['city']),
    ].where((part) => part.isNotEmpty).join(', ');

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
                  _extractString(profile['category_name']).isNotEmpty
                      ? _extractString(profile['category_name'])
                      : _extractString(profile['category_slug']).isEmpty
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
                _profileRow('Address', address),
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
          if (canEditProfile)
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                key: const Key('merchant_edit_business_profile'),
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => _showEditProfileDialog(profile),
                label: const Text('Edit Business Profile'),
              ),
            )
          else
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text(
                'Only the business owner can edit this profile.',
                style: TextStyle(color: AppTheme.secondaryText),
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

  Widget _viewMetricCard({
    required String title,
    required int? value,
    required IconData icon,
    required Color color,
  }) {
    return PremiumCard(
      borderColor: color.withValues(alpha: 0.2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(height: 12),
          Text(
            value?.toString() ?? '—',
            key: Key(
              'merchant_view_metric_${title.toLowerCase().replaceAll(' ', '_')}',
            ),
            style: const TextStyle(
              fontSize: 25,
              fontWeight: FontWeight.w800,
              color: AppTheme.mainText,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppTheme.secondaryText,
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
    VoidCallback onTap, {
    Key? key,
  }) {
    return Material(
      key: key,
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
              Expanded(
                child: Text(
                  r.customerName.isEmpty ? 'Customer request' : r.customerName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppTheme.mainText,
                  ),
                ),
              ),
              const SizedBox(width: 10),
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
              ] else if (r.status == 'accepted' ||
                  r.status == 'rescheduled') ...[
                Expanded(
                  child: OutlinedButton.icon(
                    key: Key('merchant_reschedule_request_${r.id}'),
                    onPressed: () => _rescheduleRequest(r),
                    icon: const Icon(Icons.event_repeat_rounded),
                    label: Text(
                      r.status == 'rescheduled'
                          ? 'Change proposed time'
                          : 'Reschedule',
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.primary,
                      side: const BorderSide(color: AppTheme.primary),
                    ),
                  ),
                ),
                if (r.status == 'accepted') ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      key: Key('merchant_start_request_${r.id}'),
                      onPressed: () => _updateRequest(r.id, 'in_progress'),
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: const Text('Start work'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.success,
                        side: const BorderSide(color: AppTheme.success),
                      ),
                    ),
                  ),
                ],
              ] else if (r.status == 'in_progress') ...[
                Expanded(
                  child: ElevatedButton.icon(
                    key: Key('merchant_complete_request_${r.id}'),
                    onPressed: () => _updateRequest(r.id, 'completed'),
                    icon: const Icon(Icons.check_rounded),
                    label: const Text('Mark complete'),
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

  Future<void> _rescheduleRequest(MerchantServiceRequest request) async {
    String? businessId =
        ref.read(merchantProfileProvider('')).profile?['id'] as String?;
    if (businessId == null || businessId.isEmpty) {
      try {
        final response = await apiClient.get('/merchant/profile');
        businessId =
            (response.data['data'] as Map<String, dynamic>)['id'] as String?;
      } catch (_) {
        businessId = null;
      }
    }
    if (businessId == null || businessId.isEmpty || !mounted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not load this business schedule.'),
          ),
        );
      }
      return;
    }

    final today = DateUtils.dateOnly(DateTime.now());
    final earliest = today.add(const Duration(days: 1));
    final currentDate = request.requestedLocalDate != null
        ? DateTime.tryParse('${request.requestedLocalDate}T00:00:00')
        : DateTime.tryParse(request.requestedFor ?? '')?.toLocal();
    final initialDate = currentDate != null && !currentDate.isBefore(earliest)
        ? DateUtils.dateOnly(currentDate)
        : earliest;
    final selectedDate = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: earliest,
      lastDate: today.add(const Duration(days: 180)),
      helpText: 'Choose a new appointment date',
    );
    if (selectedDate == null || !mounted) return;

    final dateKey = DateFormat('yyyy-MM-dd').format(selectedDate);
    List<Map<String, dynamic>> slots;
    try {
      final response = await apiClient.get(
        '/merchant/businesses/$businessId/availability',
        queryParameters: {'from': dateKey, 'to': dateKey},
      );
      final data = response.data['data'] as Map<String, dynamic>;
      final allSlots = (data['slots'] as List<dynamic>? ?? const [])
          .cast<Map<String, dynamic>>();
      final now = DateTime.now().toUtc();
      slots = allSlots.where((slot) {
        final startsAt = DateTime.tryParse(slot['starts_at'] as String? ?? '');
        return slot['status'] == 'open' &&
            (slot['remaining_capacity'] as num? ?? 0) > 0 &&
            slot['id'] != request.slotId &&
            startsAt != null &&
            startsAt.isAfter(now);
      }).toList();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not load available times. Try again.'),
          ),
        );
      }
      return;
    }
    if (!mounted) return;
    if (slots.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No available appointments on that date.'),
        ),
      );
      return;
    }

    if (!mounted) return;
    final chosenSlot = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        String? selectedSlotId;
        return StatefulBuilder(
          builder: (context, setSheetState) => SafeArea(
            child: Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.72,
              ),
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 42,
                      height: 4,
                      decoration: BoxDecoration(
                        color: const Color(0xFFCBD5E1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Choose a new appointment time',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    DateFormat('EEEE, d MMMM').format(selectedDate),
                    style: const TextStyle(color: AppTheme.secondaryText),
                  ),
                  const SizedBox(height: 12),
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: slots.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final slot = slots[index];
                        final id = slot['id'] as String;
                        final start = slot['local_starts_at'] as String? ?? '';
                        final end = slot['local_ends_at'] as String? ?? '';
                        final startLabel = DateFormat('h:mm a')
                            .format(DateTime.parse('2000-01-01T$start:00'));
                        final endLabel = DateFormat('h:mm a')
                            .format(DateTime.parse('2000-01-01T$end:00'));
                        return Material(
                          color: Colors.transparent,
                          child: ListTile(
                            key: Key('merchant_reschedule_slot_$id'),
                            leading: Icon(
                              key: Key('merchant_reschedule_selected_$id'),
                              selectedSlotId == id
                                  ? Icons.radio_button_checked
                                  : Icons.radio_button_unchecked,
                              color: selectedSlotId == id
                                  ? AppTheme.primary
                                  : AppTheme.secondaryText,
                            ),
                            title: Text('$startLabel – $endLabel'),
                            subtitle: Text(
                              '${slot['remaining_capacity']} appointments available',
                            ),
                            contentPadding: EdgeInsets.zero,
                            onTap: () =>
                                setSheetState(() => selectedSlotId = id),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      key: const Key('merchant_reschedule_confirm'),
                      onPressed: selectedSlotId == null
                          ? null
                          : () => Navigator.of(sheetContext).pop(
                              slots.singleWhere(
                                (slot) => slot['id'] == selectedSlotId,
                              ),
                            ),
                      child: const Text('Send new time to customer'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    if (chosenSlot == null || !mounted) return;

    final success = await ref
        .read(merchantProvider.notifier)
        .rescheduleRequest(businessId, request.id, chosenSlot['id'] as String);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success
                ? 'New appointment time sent to the customer.'
                : 'Could not reschedule. The slot may no longer be available.',
          ),
        ),
      );
    }
  }

  Future<void> _showEditProfileDialog(Map<String, dynamic> profile) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _MerchantProfileEditDialog(
        profile: profile,
        onSave: (updates) =>
            ref.read(merchantProfileProvider('').notifier).update(updates),
      ),
    );
    if (saved == true && mounted) {
      await ref.read(merchantProfileProvider('').notifier).load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Business profile updated.')),
        );
      }
    }
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

class _MerchantProfileEditDialog extends StatefulWidget {
  const _MerchantProfileEditDialog({
    required this.profile,
    required this.onSave,
  });

  final Map<String, dynamic> profile;
  final Future<bool> Function(Map<String, dynamic> updates) onSave;

  @override
  State<_MerchantProfileEditDialog> createState() =>
      _MerchantProfileEditDialogState();
}

class _MerchantProfileEditDialogState
    extends State<_MerchantProfileEditDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _addressController;
  late final TextEditingController _phoneController;
  late String _city;
  late String _coverPhotoUrl;
  bool _isSaving = false;
  bool _isUploading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: _value('name'));
    _descriptionController = TextEditingController(text: _value('description'));
    _addressController = TextEditingController(text: _value('address_text'));
    _phoneController = TextEditingController(text: _value('phone_e164'));
    _city = _value('city') == 'Jajpur' ? 'Jajpur' : 'Cuttack';
    _coverPhotoUrl = _value('cover_photo_url');
  }

  String _value(String key) => widget.profile[key]?.toString() ?? '';

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _addressController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final image = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 85,
    );
    if (image == null || !mounted) return;
    setState(() {
      _isUploading = true;
      _error = null;
    });
    try {
      final upload = await ApiClient().uploadMedia(
        bytes: await image.readAsBytes(),
        filename: image.name,
        purpose: 'storefront',
      );
      if (!mounted) return;
      setState(() => _coverPhotoUrl = upload['url'] as String? ?? '');
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Photo upload failed. Check your connection and retry.';
        });
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _isSaving = true;
      _error = null;
    });
    final updates = <String, dynamic>{
      'name': _nameController.text.trim(),
      'description': _descriptionController.text.trim(),
      'address_text': _addressController.text.trim(),
      'city': _city,
      'phone_e164': _phoneController.text.trim(),
    };
    if (_coverPhotoUrl.isNotEmpty) {
      updates['cover_photo_url'] = _coverPhotoUrl;
    }
    final saved = await widget.onSave(updates);
    if (!mounted) return;
    if (saved) {
      Navigator.pop(context, true);
    } else {
      setState(() {
        _isSaving = false;
        _error = 'Could not save the profile. Please retry.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit business profile'),
      content: SizedBox(
        width: 440,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.62,
          ),
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_coverPhotoUrl.isNotEmpty)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Image.network(
                        ApiClient().resolveMediaUrl(_coverPhotoUrl),
                        height: 130,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const SizedBox.shrink(),
                      ),
                    ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: _isUploading || _isSaving ? null : _pickPhoto,
                      icon: _isUploading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.add_a_photo_outlined),
                      label: const Text('Change storefront photo'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const Key('merchant_profile_name'),
                    controller: _nameController,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Business name',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Enter a business name'
                        : value.trim().length > 160
                        ? 'Business name must be 160 characters or fewer'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _descriptionController,
                    maxLines: 3,
                    maxLength: 1000,
                    decoration: const InputDecoration(
                      labelText: 'About your business',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const Key('merchant_profile_address'),
                    controller: _addressController,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Street address',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Enter a street address'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    key: const Key('merchant_profile_city'),
                    initialValue: _city,
                    decoration: const InputDecoration(
                      labelText: 'City',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'Cuttack',
                        child: Text('Cuttack'),
                      ),
                      DropdownMenuItem(value: 'Jajpur', child: Text('Jajpur')),
                    ],
                    onChanged: _isSaving
                        ? null
                        : (value) {
                            if (value != null) setState(() => _city = value);
                          },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Business phone (+country code)',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      final phone = value?.trim() ?? '';
                      if (phone.isEmpty) return null;
                      return RegExp(r'^\+[1-9]\d{7,14}$').hasMatch(phone)
                          ? null
                          : 'Use international format, e.g. +919876543210';
                    },
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        _error!,
                        style: const TextStyle(color: AppTheme.error),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          key: const Key('merchant_save_profile'),
          onPressed: _isSaving || _isUploading ? null : _save,
          icon: _isSaving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.check),
          label: Text(_isSaving ? 'Saving' : 'Save changes'),
        ),
      ],
    );
  }
}
