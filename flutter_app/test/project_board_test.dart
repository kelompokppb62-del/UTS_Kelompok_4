import 'package:flutter_test/flutter_test.dart';
import 'package:katyuflow/features/auth/models/account.dart';
import 'package:katyuflow/features/projects/models/work_project.dart';
import 'package:katyuflow/features/projects/services/project_board.dart';
import 'package:katyuflow/features/projects/services/project_repository.dart';

void main() {
  const owner = Account(id: 'owner', role: UserRole.owner);
  const worker = Account(id: 'worker', role: UserRole.worker);
  const otherWorker = Account(id: 'other', role: UserRole.worker);
  const draft = NewProjectDraft(
    title: 'Setup',
    client: 'Client',
    packageName: 'Basic',
    brief: '',
  );
  late DateTime now;
  late ProjectBoard board;

  setUp(() {
    now = DateTime(2026, 11, 15, 23, 59);
    board = ProjectBoard(InMemoryProjectRepository([]), now: () => now);
  });
  tearDown(() => board.dispose());

  test(
    'Claims are exclusive and each worker gets three per local calendar day',
    () {
      final ids = List.generate(5, (_) => board.publish(owner, draft)!.id);
      expect(board.publish(worker, draft), isNull);
      expect(board.claim(owner, ids.first), ProjectResult.forbidden);
      for (final id in ids.take(3)) {
        expect(board.claim(worker, id), ProjectResult.claimed);
      }
      expect(board.claim(otherWorker, ids.first), ProjectResult.unavailable);
      expect(board.claim(worker, ids[3]), ProjectResult.quota);
      expect(board.claim(otherWorker, ids[3]), ProjectResult.claimed);
      expect(board.claimsToday(worker), 3);
      expect(board.claimsToday(otherWorker), 1);

      now = DateTime(2026, 11, 16);
      expect(board.claimsToday(worker), 0);
      expect(board.claim(worker, ids.last), ProjectResult.claimed);
      expect(board.assignedTo(worker).length, 4);
    },
  );

  test(
    'Review permits revision and awards points only once after approval',
    () {
      final project = board.publish(owner, draft)!;
      final id = project.id;
      expect(
        board.review(owner, id, approved: true),
        ProjectResult.invalidStatus,
      );
      expect(board.claim(worker, id), ProjectResult.claimed);
      expect(board.advance(otherWorker, id), ProjectResult.forbidden);
      expect(board.advance(owner, id), ProjectResult.forbidden);

      void submit() {
        for (final status in [
          ProjectStatus.working,
          ProjectStatus.almostDone,
          ProjectStatus.waitingReview,
        ]) {
          expect(board.advance(worker, id), ProjectResult.updated);
          expect(board.projectById(id)?.status, status);
        }
        expect(board.advance(worker, id), ProjectResult.invalidStatus);
        expect(board.earnedPoints(worker), 0);
      }

      submit();
      expect(board.review(worker, id, approved: true), ProjectResult.forbidden);
      expect(board.review(owner, id, approved: false), ProjectResult.revision);
      expect(board.projectById(id)?.status, ProjectStatus.revision);
      expect(board.earnedPoints(worker), 0);
      submit();
      expect(board.review(owner, id, approved: true), ProjectResult.approved);
      expect(
        board.review(owner, id, approved: true),
        ProjectResult.invalidStatus,
      );
      expect(board.projectById(id)?.status, ProjectStatus.completed);
      expect(board.earnedPoints(worker), project.points);
      expect(board.earnedPoints(otherWorker), 0);
      expect(board.claimsToday(worker), 1);
    },
  );
}
