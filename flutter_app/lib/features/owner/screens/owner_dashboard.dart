import 'package:flutter/material.dart';

import '../../../core/widgets/dashboard_shell.dart';
import '../../../core/widgets/metric_card.dart';
import '../../../core/widgets/notice.dart';
import '../../../core/widgets/page_list.dart';
import '../../auth/models/account.dart';
import '../../projects/models/work_project.dart';
import '../../projects/screens/project_details.dart';
import '../../projects/services/project_workspace.dart';
import '../../projects/widgets/new_project_dialog.dart';
import '../widgets/worker_directory.dart';
import '../../worker/screens/worker_performance.dart';

class OwnerDashboard extends StatefulWidget {
  const OwnerDashboard({
    super.key,
    required this.owner,
    required this.board,
    required this.onLogout,
  });

  final Account owner;
  final ProjectWorkspace board;
  final VoidCallback onLogout;

  @override
  State<OwnerDashboard> createState() => _OwnerDashboardState();
}

class _OwnerDashboardState extends State<OwnerDashboard> {
  int _tab = 0;
  bool _publishing = false;

  Future<void> _publishProject() async {
    final draft = await showDialog<NewProjectDraft>(
      context: context,
      builder: (_) => NewProjectDialog(serverNow: widget.board.serverNow),
    );
    if (!mounted || draft == null) return;
    setState(() => _publishing = true);
    try {
      await widget.board.publishDraft(widget.owner, draft);
      if (!mounted) return;
      setState(() => _tab = 1);
      showNotice(context, 'Project dipublikasikan.');
    } on ProjectRequestException catch (error) {
      if (mounted) showNotice(context, error.message);
    } catch (_) {
      if (mounted) {
        showNotice(
          context,
          'Publikasi gagal. Periksa daftar project sebelum mencoba lagi.',
        );
      }
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
  }

  @override
  Widget build(BuildContext context) => DashboardShell(
    title: 'Dashboard Owner',
    tab: _tab,
    onTab: (tab) => setState(() => _tab = tab),
    onLogout: widget.onLogout,
    destinations: const [
      NavigationDestination(
        icon: Icon(Icons.dashboard_outlined),
        label: 'Ringkasan',
      ),
      NavigationDestination(icon: Icon(Icons.work_outline), label: 'Project'),
      NavigationDestination(icon: Icon(Icons.people_outline), label: 'Worker'),
      NavigationDestination(
        icon: Icon(Icons.leaderboard_outlined),
        label: 'Leaderboard',
      ),
    ],
    body: _tab == 2
        ? WorkerDirectory(workspace: widget.board, owner: widget.owner)
        : _tab == 3
        ? WorkerLeaderboard(workspace: widget.board)
        : ListenableBuilder(
            listenable: widget.board,
            builder: (context, _) {
              final workspace = widget.board;
              if (workspace.error case final message?) {
                return PageList(children: [Text(message)]);
              }
              if (workspace.isLoading) {
                return const Center(
                  child: CircularProgressIndicator(
                    semanticsLabel: 'Memuat project',
                  ),
                );
              }
              final projects = widget.board.projects.toList()
                ..sort((a, b) {
                  if (a.status == ProjectStatus.completed &&
                      b.status != ProjectStatus.completed) {
                    return 1;
                  }
                  if (b.status == ProjectStatus.completed &&
                      a.status != ProjectStatus.completed) {
                    return -1;
                  }
                  return a.effectiveDeadline.compareTo(b.effectiveDeadline);
                });
              final urgent = projects
                  .where((p) => p.needsDeadlineAttention(workspace.serverNow))
                  .length;
              final available = projects
                  .where((p) => p.status == ProjectStatus.available)
                  .length;
              final completed = projects
                  .where((p) => p.status == ProjectStatus.completed)
                  .length;
              final inProgress = projects.length - available - completed;
              final visible = _tab == 0 ? projects.take(3) : projects;
              return PageList(
                key: ValueKey(_tab),
                children: [
                  Text(
                    _tab == 0 ? 'Ringkasan project' : 'Semua Project',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Pantau pesanan setup server Discord dan tinjau hasil pekerjaan.',
                  ),
                  if (urgent > 0)
                    Text('$urgent project mendekati atau lewat deadline.'),
                  const SizedBox(height: 20),
                  if (_tab == 0) ...[
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final gap = 10.0;
                        final columns = constraints.maxWidth >= 560
                            ? 4
                            : constraints.maxWidth >= 245
                            ? 2
                            : 1;
                        final width =
                            (constraints.maxWidth - (columns - 1) * gap) /
                            columns;
                        return Wrap(
                          spacing: gap,
                          runSpacing: gap,
                          children: [
                            SizedBox(
                              width: width,
                              child: MetricCard(
                                label: 'Total project',
                                value: '${projects.length}',
                                icon: Icons.folder_outlined,
                              ),
                            ),
                            SizedBox(
                              width: width,
                              child: MetricCard(
                                label: 'Tersedia',
                                value: '$available',
                                icon: Icons.inbox_outlined,
                              ),
                            ),
                            SizedBox(
                              width: width,
                              child: MetricCard(
                                label: 'Diproses',
                                value: '$inProgress',
                                icon: Icons.autorenew,
                              ),
                            ),
                            SizedBox(
                              width: width,
                              child: MetricCard(
                                label: 'Selesai',
                                value: '$completed',
                                icon: Icons.check_circle_outline,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 18),
                  ],
                  FilledButton.icon(
                    onPressed: _publishing ? null : _publishProject,
                    icon: const Icon(Icons.add),
                    label: Text(
                      _publishing ? 'Mempublikasikan…' : 'Tambah project',
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (_tab == 0) ...[
                    Text(
                      'Prioritas deadline',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (visible.isEmpty) const Text('Belum ada project.'),
                  for (final project in visible)
                    BoardProjectCard(
                      key: ValueKey(project.id),
                      project: project,
                      board: widget.board,
                      account: widget.owner,
                    ),
                ],
              );
            },
          ),
  );
}
