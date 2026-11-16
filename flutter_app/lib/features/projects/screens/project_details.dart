import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/widgets/notice.dart';
import '../../../core/widgets/page_list.dart';
import '../../auth/models/account.dart';
import '../models/work_project.dart';
import '../services/project_workspace.dart';
import '../widgets/project_card.dart';
import 'project_collaboration_pages.dart';
import 'project_review_forms.dart';

class ProjectDetails extends StatelessWidget {
  const ProjectDetails({
    super.key,
    required this.board,
    required this.account,
    required this.projectId,
  });

  final ProjectWorkspace board;
  final Account account;
  final String projectId;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Detail Project')),
    body: SafeArea(
      top: false,
      child: ListenableBuilder(
        listenable: board,
        builder: (context, _) {
          if (board.error case final message?) {
            return PageList(children: [Text(message)]);
          }
          final project = board.projectById(projectId);
          if (project == null ||
              (account.role == UserRole.worker &&
                  project.status != ProjectStatus.available &&
                  project.claimedBy != account.id)) {
            return const Center(child: Text('Project tidak tersedia.'));
          }
          return PageList(
            children: [
              BoardProjectCard(
                project: project,
                board: board,
                account: account,
                details: true,
                onClaim: () {
                  if (context.mounted &&
                      ModalRoute.of(context)?.isCurrent == true) {
                    Navigator.of(context).pop(true);
                  }
                },
              ),
              if (account.role == UserRole.owner ||
                  project.claimedBy == account.id) ...[
                if (project.claimedBy != null)
                  OutlinedButton.icon(
                    icon: const Icon(Icons.forum_outlined),
                    label: const Text('Diskusi Project'),
                    onPressed: () => Navigator.of(context).push<void>(
                      MaterialPageRoute(
                        builder: (_) => ProjectDiscussion(
                          board: board,
                          account: account,
                          project: project,
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                ProjectChecklist(
                  board: board,
                  account: account,
                  project: project,
                ),
                const SizedBox(height: 18),
                Text(
                  'Riwayat Project',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                ProjectHistory(board: board, project: project),
              ],
            ],
          );
        },
      ),
    ),
  );
}

class BoardProjectCard extends StatefulWidget {
  const BoardProjectCard({
    super.key,
    required this.project,
    required this.board,
    required this.account,
    this.details = false,
    this.onClaim,
  });

  final WorkProject project;
  final ProjectWorkspace board;
  final Account account;
  final bool details;
  final VoidCallback? onClaim;

  @override
  State<BoardProjectCard> createState() => _BoardProjectCardState();
}

class _BoardProjectCardState extends State<BoardProjectCard> {
  bool _busy = false;

  Future<void> _run(FutureOr<ProjectResult> Function() command) async {
    if (_busy) return;
    setState(() => _busy = true);
    final onClaim = widget.onClaim;
    ProjectResult result;
    try {
      result = await command();
    } catch (_) {
      result = ProjectResult.failed;
    }
    if (mounted) {
      setState(() => _busy = false);
      showNotice(context, result.message);
    }
    if (result == ProjectResult.claimed) onClaim?.call();
  }

  @override
  Widget build(BuildContext context) {
    final project = widget.project;
    final account = widget.account;
    final board = widget.board;
    final owner = account.role == UserRole.owner;
    final mine = project.claimedBy == account.id;
    final review = owner && project.status == ProjectStatus.waitingReview;
    final action = owner
        ? null
        : switch (project.status) {
            ProjectStatus.available => 'Klaim project',
            ProjectStatus.claimed when mine => 'Mulai pengerjaan',
            ProjectStatus.working when mine => 'Tandai hampir selesai',
            ProjectStatus.almostDone when mine => 'Kirim untuk review',
            ProjectStatus.revision when mine => 'Kerjakan revisi',
            _ => null,
          };
    Future<void> openForm({required bool isRevision}) async {
      final result = await Navigator.of(context).push<ProjectResult>(
        MaterialPageRoute(
          builder: (_) => ProjectReviewForm(
            account: account,
            board: board,
            project: project,
            isRevision: isRevision,
          ),
        ),
      );
      if (context.mounted && result != null) {
        showNotice(context, result.message);
      }
    }

    void approve() => _run(
      () => board.review(
        account,
        project.id,
        approved: true,
        expectedActivityId: project.activityId,
      ),
    );
    return ProjectCard(
      project: project,
      serverNow: board.serverNow,
      busy: _busy,
      showDetails: widget.details,
      onDetails: widget.details || _busy
          ? null
          : () async {
              final onClaim = widget.onClaim;
              final claimed = await Navigator.of(context).push<bool>(
                MaterialPageRoute(
                  builder: (_) => ProjectDetails(
                    board: board,
                    account: account,
                    projectId: project.id,
                  ),
                ),
              );
              if (claimed == true) onClaim?.call();
            },
      mainActionLabel: action,
      onMainAction: action == null
          ? null
          : project.status == ProjectStatus.almostDone
          ? () => openForm(isRevision: false)
          : () => _run(
              () => project.status == ProjectStatus.available
                  ? board.claim(account, project.id)
                  : board.advance(
                      account,
                      project.id,
                      expectedStatus: project.status,
                    ),
            ),
      onResubmit: mine && project.status == ProjectStatus.revision
          ? () => openForm(isRevision: false)
          : null,
      onApprove: review && widget.details ? approve : null,
      onRevision: review && widget.details
          ? () => openForm(isRevision: true)
          : null,
    );
  }
}
