import 'package:flutter/material.dart';
import 'package:grepmind_mobile/core/theme/app_theme.dart';
import 'package:grepmind_mobile/core/widgets/premium_card.dart';

/// Profile screen: location, service requests, settings, support.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Profile'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(kScreenPadding),
        children: [
          // Profile header.
          PremiumCard(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: AppTheme.primaryContainer,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Icon(Icons.person, color: AppTheme.primary, size: 30),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Customer',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppTheme.mainText),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '+91 98765 43210',
                        style: TextStyle(fontSize: 14, color: AppTheme.secondaryText),
                      ),
                    ],
                  ),
                ),
                TextButton(onPressed: () {}, child: const Text('Edit')),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Location.
          const Text(
            'Location',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.secondaryText),
          ),
          const SizedBox(height: 8),
          PremiumCard(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.location_on_outlined, color: AppTheme.primary, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Bhubaneswar, Odisha',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppTheme.mainText),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Manual selection',
                        style: TextStyle(fontSize: 12, color: AppTheme.secondaryText),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.edit_outlined, color: AppTheme.hintText, size: 20),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Service requests.
          const Text(
            'Service requests',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.secondaryText),
          ),
          const SizedBox(height: 8),
          PremiumCard(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'No active requests',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppTheme.mainText),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Request plumbing, electrical, carpentry and more.',
                      style: TextStyle(fontSize: 12, color: AppTheme.secondaryText),
                    ),
                  ],
                ),
                const Icon(Icons.chevron_right, color: AppTheme.hintText, size: 20),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Settings.
          const Text(
            'Settings & support',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.secondaryText),
          ),
          const SizedBox(height: 8),
          _menuItem(Icons.language, 'Language', 'English'),
          const Divider(height: 1, color: AppTheme.border),
          _menuItem(Icons.notifications_outlined, 'Notification preferences', 'Manage alerts'),
          const Divider(height: 1, color: AppTheme.border),
          _menuItem(Icons.privacy_tip_outlined, 'Privacy & data', 'Location and consent'),
          const Divider(height: 1, color: AppTheme.border),
          _menuItem(Icons.help_outline, 'Help & support', 'Contact us'),
          const Divider(height: 1, color: AppTheme.border),
          _menuItem(Icons.logout, 'Sign out', '', isDestructive: true),
        ],
      ),
    );
  }

  Widget _menuItem(IconData icon, String title, String subtitle, {bool isDestructive = false}) {
    return ListTile(
      leading: Icon(icon, color: isDestructive ? AppTheme.error : AppTheme.primary, size: 22),
      title: Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: isDestructive ? AppTheme.error : AppTheme.mainText)),
      subtitle: subtitle.isNotEmpty
          ? Text(subtitle, style: const TextStyle(fontSize: 12, color: AppTheme.secondaryText))
          : null,
      trailing: const Icon(Icons.chevron_right, color: AppTheme.hintText, size: 20),
      onTap: () {},
    );
  }
}
