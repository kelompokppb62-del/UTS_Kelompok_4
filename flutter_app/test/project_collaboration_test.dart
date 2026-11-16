import "dart:typed_data";

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as images;
import 'package:katyuflow/features/projects/models/project_collaboration.dart';
import 'package:katyuflow/features/projects/models/work_project.dart';
import 'package:katyuflow/features/projects/screens/project_review_forms.dart';
import 'package:katyuflow/features/projects/widgets/project_deadline.dart';

void main() {
  test(
    'links allow Discord invites and HTTPS proof with a network hostname',
    () {
      expect(
        WorkSubmission.validDiscord('https://discord.gg/KatyuFlow'),
        isTrue,
      );
      expect(
        WorkSubmission.validDiscord('https://discord.com/invite/Test_1'),
        isTrue,
      );
      for (final url in [
        'https://discord.gg.example.test/KatyuFlow',
        'https://discord.gg@evil.test/KatyuFlow',
        'http://discord.gg/KatyuFlow',
      ]) {
        expect(WorkSubmission.validDiscord(url), isFalse);
      }
      expect(
        WorkSubmission.validHttps('https://example.test/proof?key=a%20b'),
        isTrue,
      );
      expect(
        WorkSubmission.validHttps('https://user@example.test/path'),
        isFalse,
      );
      expect(WorkSubmission.validHttps('javascript:alert(1)'), isFalse);
    },
  );

  test(
    'image is resized, stripped of EXIF and encoded within the JPEG cap',
    () {
      final original = images.Image(width: 1500, height: 200);
      original.exif.imageIfd.imageDescription = 'private metadata';
      final encoded = compressRevisionImage(images.encodeJpg(original))!;
      expect(encoded.length, lessThanOrEqualTo(RevisionRequest.maxImageBytes));
      expect(isDisplayableRevisionImage(encoded), isTrue);
      expect(isDisplayableRevisionImage(images.encodeJpg(original)), isFalse);
      final decoded = images.decodeJpg(encoded)!;
      expect(decoded.width, 1200);
      expect(decoded.height, 160);
      expect(decoded.exif.isEmpty, isTrue);
      expect(compressRevisionImage(Uint8List.fromList([1, 2, 3])), isNull);
    },
  );

  test(
    'deadline reminders use supplied server instant and WIB revision deadline',
    () {
      final now = DateTime.utc(2026, 11, 16, 10);
      final project = WorkProject(
        id: 'project',
        title: 'Project',
        client: 'Client',
        packageName: 'Basic',
        brief: '',
        deadline: now.subtract(const Duration(days: 1)),
        status: ProjectStatus.working,
      );
      expect(
        deadlineReminder(project, null, detail: true),
        'Menunggu waktu server',
      );
      expect(deadlineReminder(project, now), startsWith('Overdue'));
      final revision = project.withStatus(
        ProjectStatus.revision,
        revisionDue: now.add(const Duration(hours: 2)),
      );
      expect(deadlineReminder(revision, now), contains('2 jam'));
      expect(wibDateTime(revision.effectiveDeadline), '16/11/2026 19:00 WIB');
      expect(
        deadlineReminder(revision.withStatus(ProjectStatus.waitingReview), now),
        isNull,
      );
    },
  );
}
