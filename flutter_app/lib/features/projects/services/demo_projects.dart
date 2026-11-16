import '../models/work_project.dart';

List<WorkProject> demoProjects(DateTime now) => [
  WorkProject(
    id: 'KF-101',
    title: 'TARAHOOD Gaming Community',
    client: 'Client Tarahood',
    packageName: 'Full Setup',
    brief: 'Server gaming tema Y2K, welcome, roles, dan notifikasi live.',
    deadline: now.add(const Duration(days: 2)),
    points: 120,
  ),
  WorkProject(
    id: 'KF-102',
    title: 'Roblox Hangout Server',
    client: 'Client Roblox',
    packageName: 'Basic',
    brief: 'Channel mabar, temporary voice, peraturan, dan bot komunitas.',
    deadline: now.add(const Duration(days: 3)),
    points: 70,
  ),
  WorkProject(
    id: 'KF-103',
    title: 'Esports Team Server',
    client: 'Client Esports',
    packageName: 'Premium',
    brief: 'Role divisi, ticket support, log, dan sistem verifikasi.',
    deadline: now.add(const Duration(days: 4)),
    points: 150,
  ),
  WorkProject(
    id: 'KF-100',
    title: 'Cafe & Friends Community',
    client: 'Client Cafe',
    packageName: 'Full Setup',
    brief: 'Server komunitas dengan fitur musik dan event.',
    deadline: now.add(const Duration(days: 1)),
    status: ProjectStatus.working,
    claimedBy: 'dina',
  ),
];
