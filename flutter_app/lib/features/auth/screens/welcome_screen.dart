import 'package:flutter/material.dart';

import 'package:katyuflow/app/theme.dart';
import 'package:katyuflow/core/widgets/page_list.dart';
import 'package:katyuflow/features/auth/models/account.dart';
import 'package:katyuflow/features/updates/android_update_button.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key, required this.onChoose, this.modeLabel});

  final ValueChanged<UserRole> onChoose;
  final String? modeLabel;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: PageList(
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 56),
            const Icon(Icons.hub_rounded, size: 58, color: AppColors.teal),
            const SizedBox(height: 18),
            const Text(
              'KatyuFlow',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 34,
                fontWeight: FontWeight.bold,
                color: AppColors.navy,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Kelola pesanan setup server Discord, pantau progres, dan beri reward dalam satu tempat.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.muted),
            ),
            const SizedBox(height: 55),
            const Text(
              'Masuk sebagai',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 21),
            ),
            const SizedBox(height: 16),
            RoleTile(
              title: 'Login as Owner',
              subtitle: 'Input order, monitoring worker, dan review project.',
              icon: Icons.admin_panel_settings_rounded,
              color: AppColors.navy,
              onTap: () => onChoose(UserRole.owner),
            ),
            const SizedBox(height: 14),
            RoleTile(
              title: 'Login as Worker',
              subtitle: 'Klaim project, update progress, dan kumpulkan poin.',
              icon: Icons.construction_rounded,
              color: AppColors.teal,
              onTap: () => onChoose(UserRole.worker),
            ),
            const SizedBox(height: 25),
            if (showAndroidUpdates) const Center(child: AndroidUpdateButton()),
            if (modeLabel case final label?)
              Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: AppColors.muted),
              ),
          ],
        ),
      ),
    );
  }
}

class RoleTile extends StatelessWidget {
  const RoleTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
  });
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: color.withValues(alpha: 0.12),
                radius: 28,
                child: Icon(icon, color: color, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
            ],
          ),
        ),
      ),
    );
  }
}
