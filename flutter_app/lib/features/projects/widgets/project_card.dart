import 'package:flutter/material.dart';

import 'package:katyuflow/app/theme.dart';
import 'package:katyuflow/features/projects/models/work_project.dart';

import 'project_deadline.dart';

class ProjectCard extends StatelessWidget {
  const ProjectCard({
    super.key,
    required this.project,
    this.showDetails = false,
    this.serverNow,
    this.onResubmit,
    this.onDetails,
    this.onApprove,
    this.onRevision,
    this.mainActionLabel,
    this.onMainAction,
    this.busy = false,
  });

  final WorkProject project;
  final DateTime? serverNow;
  final VoidCallback? onResubmit;
  final bool busy;
  final bool showDetails;
  final VoidCallback? onDetails;
  final String? mainActionLabel;
  final VoidCallback? onMainAction;
  final VoidCallback? onApprove;
  final VoidCallback? onRevision;

  @override
  Widget build(BuildContext context) {
    final reminder = deadlineReminder(project, serverNow, detail: showDetails);
    final statusColor = project.status == ProjectStatus.available
        ? AppColors.teal
        : project.status == ProjectStatus.completed
        ? Colors.green.shade700
        : project.status == ProjectStatus.revision
        ? Colors.deepOrange
        : AppColors.navy;
    return Card(
      elevation: 0,
      color: Colors.white,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(17)),
      child: Padding(
        padding: const EdgeInsets.all(17),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  project.id,
                  style: const TextStyle(
                    color: AppColors.teal,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Container(
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 6,
                  ),
                  child: Text(
                    statusText(project.status),
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              project.title,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: AppColors.text,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              project.isListing
                  ? project.packageName
                  : '${project.client}  •  ${project.packageName}',
              style: const TextStyle(fontSize: 12, color: AppColors.muted),
            ),
            const SizedBox(height: 10),
            if (showDetails)
              Text(
                project.isListing
                    ? 'Brief lengkap tersedia setelah project diklaim.'
                    : project.brief,
                style: const TextStyle(color: AppColors.text),
              ),
            const SizedBox(height: 12),
            Text(
              'Deadline: ${wibDateTime(project.effectiveDeadline)}  •  +${project.points} poin',
              style: const TextStyle(fontSize: 12, color: AppColors.muted),
            ),
            if (reminder != null)
              Text(
                reminder,
                style: TextStyle(
                  fontSize: 12,
                  color: project.needsDeadlineAttention(serverNow)
                      ? Colors.deepOrange.shade900
                      : AppColors.muted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            if (project.claimedBy != null) ...[
              const SizedBox(height: 5),
              Text(
                'Worker: ${switch (project.assignedWorkerName ?? project.claimedBy) {
                  'dina' => 'Dina',
                  'worker@katyuflow.app' => 'Worker Demo',
                  final worker => worker,
                }}',
                style: const TextStyle(fontSize: 12, color: AppColors.muted),
              ),
            ],
            if (busy)
              const LinearProgressIndicator(
                semanticsLabel: 'Memproses project',
              ),
            if (onDetails != null)
              TextButton(
                onPressed: onDetails,
                child: const Text('Lihat detail'),
              ),
            if (onMainAction != null && mainActionLabel != null) ...[
              const SizedBox(height: 15),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: busy ? null : onMainAction,
                  child: Text(mainActionLabel!),
                ),
              ),
            ],
            if (onResubmit != null)
              TextButton(
                onPressed: busy ? null : onResubmit,
                child: const Text('Kirim hasil revisi'),
              ),
            if (onApprove != null && onRevision != null) ...[
              const SizedBox(height: 13),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: busy ? null : onRevision,
                    child: const Text('Minta revisi'),
                  ),
                  FilledButton(
                    onPressed: busy ? null : onApprove,
                    child: const Text('Setujui'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
