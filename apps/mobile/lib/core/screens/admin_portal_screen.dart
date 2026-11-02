import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grepmind_mobile/core/providers/app_provider.dart';
import 'package:grepmind_mobile/core/screens/role_selection_screen.dart';
import 'package:grepmind_mobile/core/theme/app_theme.dart';
import 'package:grepmind_mobile/core/widgets/premium_card.dart';

/// Platform Administrator Portal screen for listing moderation,
/// claim verification, and system audit monitoring.
class AdminPortalScreen extends ConsumerStatefulWidget {
  const AdminPortalScreen({super.key});

  @override
  ConsumerState<AdminPortalScreen> createState() => _AdminPortalScreenState();
}

class _AdminPortalScreenState extends ConsumerState<AdminPortalScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  final List<Map<String, dynamic>> _pendingBusinesses = [];

  final List<Map<String, dynamic>> _pendingClaims = [];

  final List<Map<String, dynamic>> _auditLogs = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _approveBusiness(int index) {
    final biz = _pendingBusinesses[index];
    setState(() {
      _pendingBusinesses.removeAt(index);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${biz["name"]} approved & published successfully!'),
        backgroundColor: const Color(0xFF059669),
      ),
    );
  }

  void _rejectBusiness(int index) {
    final biz = _pendingBusinesses[index];
    setState(() {
      _pendingBusinesses.removeAt(index);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${biz["name"]} rejected.'),
        backgroundColor: const Color(0xFFDC2626),
      ),
    );
  }

  void _verifyClaim(int index) {
    final claim = _pendingClaims[index];
    setState(() {
      _pendingClaims.removeAt(index);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Claim for ${claim["business"]} approved! Ownership transferred.'),
        backgroundColor: const Color(0xFF059669),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFF7C3AED).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text(
                'ADMIN',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF7C3AED),
                  letterSpacing: 0.8,
                ),
              ),
            ),
            const SizedBox(width: 10),
            const Text('Moderation Portal'),
          ],
        ),
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: AppTheme.mainText,
        actions: [
          IconButton(
            tooltip: 'Switch Portal / Role',
            icon: const Icon(Icons.swap_horiz, color: Color(0xFF7C3AED)),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const RoleSelectionScreen(isSwitching: true)),
              );
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: const Color(0xFF7C3AED),
          indicatorColor: const Color(0xFF7C3AED),
          tabs: [
            Tab(text: 'Approvals (${_pendingBusinesses.length})'),
            Tab(text: 'Claims (${_pendingClaims.length})'),
            const Tab(text: 'Audit Logs'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildApprovalsTab(),
          _buildClaimsTab(),
          _buildAuditLogsTab(),
        ],
      ),
    );
  }

  Widget _buildApprovalsTab() {
    if (_pendingBusinesses.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.check_circle_outline, size: 56, color: Color(0xFF10B981)),
            SizedBox(height: 12),
            Text(
              'All Caught Up!',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppTheme.mainText),
            ),
            SizedBox(height: 6),
            Text('No pending merchant registrations.', style: TextStyle(color: AppTheme.secondaryText)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _pendingBusinesses.length,
      itemBuilder: (context, index) {
        final biz = _pendingBusinesses[index];
        return PremiumCard(
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.storefront, color: AppTheme.primary, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          biz['name'] as String,
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppTheme.mainText),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          biz['category'] as String,
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF0F766E)),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF3C7),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      'PENDING',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Color(0xFFD97706)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(Icons.place_outlined, size: 14, color: AppTheme.secondaryText),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      biz['locality'] as String,
                      style: const TextStyle(fontSize: 12, color: AppTheme.secondaryText),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(Icons.phone_outlined, size: 14, color: AppTheme.secondaryText),
                  const SizedBox(width: 6),
                  Text(
                    biz['phone'] as String,
                    style: const TextStyle(fontSize: 12, color: AppTheme.secondaryText),
                  ),
                  const Spacer(),
                  Text(
                    biz['date'] as String,
                    style: const TextStyle(fontSize: 11, color: AppTheme.hintText),
                  ),
                ],
              ),
              const Divider(height: 22),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFDC2626),
                        side: const BorderSide(color: Color(0xFFFCA5A5)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: () => _rejectBusiness(index),
                      child: const Text('Reject'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF059669),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        elevation: 0,
                      ),
                      onPressed: () => _approveBusiness(index),
                      child: const Text('Approve Listing'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildClaimsTab() {
    if (_pendingClaims.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.verified_user_outlined, size: 56, color: Color(0xFF10B981)),
            SizedBox(height: 12),
            Text(
              'No Claims Pending',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppTheme.mainText),
            ),
            SizedBox(height: 6),
            Text('All business ownership claims processed.', style: TextStyle(color: AppTheme.secondaryText)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _pendingClaims.length,
      itemBuilder: (context, index) {
        final claim = _pendingClaims[index];
        return PremiumCard(
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF3E8FF),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.shield_outlined, color: Color(0xFF7C3AED), size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          claim['business'] as String,
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppTheme.mainText),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          claim['method'] as String,
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF059669)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Claimant: ${claim["claimedBy"]}',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.mainText),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Document: ${claim["document"]}',
                      style: const TextStyle(fontSize: 12, color: AppTheme.secondaryText),
                    ),
                  ],
                ),
              ),
              const Divider(height: 22),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF7C3AED),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    elevation: 0,
                  ),
                  onPressed: () => _verifyClaim(index),
                  icon: const Icon(Icons.verified, size: 18),
                  label: const Text('Verify Ownership & Grant Access'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAuditLogsTab() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _auditLogs.length,
      itemBuilder: (context, index) {
        final log = _auditLogs[index];
        return PremiumCard(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.receipt_long_outlined, color: AppTheme.secondaryText, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      log['action'] as String,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.mainText),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Actor: ${log["actor"]}',
                      style: const TextStyle(fontSize: 12, color: AppTheme.secondaryText),
                    ),
                    Text(
                      'Target: ${log["target"]}',
                      style: const TextStyle(fontSize: 12, color: AppTheme.secondaryText),
                    ),
                  ],
                ),
              ),
              Text(
                log['time'] as String,
                style: const TextStyle(fontSize: 11, color: AppTheme.hintText),
              ),
            ],
          ),
        );
      },
    );
  }
}
