import 'package:flutter/material.dart';

import '../../features/updates/android_update_button.dart';

class DashboardShell extends StatelessWidget {
  const DashboardShell({
    super.key,
    required this.title,
    required this.tab,
    required this.onTab,
    required this.onLogout,
    this.onProfile,
    required this.destinations,
    required this.body,
  });

  final String title;
  final int tab;
  final ValueChanged<int> onTab;
  final VoidCallback onLogout;
  final VoidCallback? onProfile;
  final List<NavigationDestination> destinations;
  final Widget body;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      automaticallyImplyLeading: false,
      title: Text(title),
      actions: [
        if (showAndroidUpdates) const AndroidUpdateButton(compact: true),
        if (onProfile != null)
          IconButton(
            tooltip: 'Profil Worker',
            onPressed: onProfile,
            icon: const Icon(Icons.account_circle_outlined),
          ),
        IconButton(
          tooltip: 'Keluar / Ganti akun',
          onPressed: onLogout,
          icon: const Icon(Icons.logout_rounded),
        ),
      ],
    ),
    body: body,
    bottomNavigationBar: NavigationBar(
      selectedIndex: tab,
      onDestinationSelected: onTab,
      destinations: destinations,
    ),
  );
}
