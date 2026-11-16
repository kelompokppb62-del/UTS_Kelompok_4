import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../auth/models/account.dart';
import '../models/project_collaboration.dart';
import 'project_workspace.dart';

class FirestoreProjectCollaboration {
  const FirestoreProjectCollaboration(this._db, this._account);

  final FirebaseFirestore _db;
  final Account _account;

  CollectionReference<Map<String, dynamic>> _items(String id) =>
      _db.collection('projects/$id/checklist');

  Stream<List<ProjectActivity>> watchActivity(String id) => _db
      .collection('projectActivities')
      .where('projectId', isEqualTo: id)
      .snapshots(includeMetadataChanges: true)
      .confirmed()
      .map((snapshot) {
        final entries = snapshot.docs.map((entry) {
          final data = entry.data();
          final detail = data['detail'] as Map<String, dynamic>? ?? {};
          final action = data['action'] as String;
          return ProjectActivity(
            id: entry.id,
            actor: data['actorId'] as String,
            action: action,
            at: (data['timestamp'] as Timestamp).toDate(),
            submission: action == 'waiting_review'
                ? WorkSubmission(
                    detail['notes'] as String,
                    detail['discordUrl'] as String,
                    detail['proofUrl'] as String?,
                  )
                : null,
            revision: action == 'revision_required'
                ? RevisionRequest(
                    detail['title'] as String,
                    detail['description'] as String,
                    (detail['deadline'] as Timestamp?)?.toDate(),
                    const [],
                  )
                : null,
            imageCount: detail['imageCount'] as int? ?? 0,
            itemTitle: detail['title'] as String?,
          );
        }).toList();
        return entries..sort((a, b) => b.at.compareTo(a.at));
      });

  Future<List<Uint8List>> loadRevisionImages(String id) async {
    final data =
        (await _db
                .doc('revisionImages/$id')
                .get(const GetOptions(source: Source.server)))
            .data();
    return (data?['images'] as List? ?? const [])
        .map((value) => (value as Blob).bytes)
        .toList();
  }

  Stream<List<ChecklistItem>> watchChecklist(String id) =>
      _items(id)
          .snapshots(includeMetadataChanges: true)
          .confirmed()
          .map(
            (snapshot) => snapshot.docs.map((doc) {
              final data = doc.data();
              return ChecklistItem(
                doc.id,
                data['title'] as String,
                data['done'] as bool,
              );
            }).toList()..sort((a, b) => a.title.compareTo(b.title)),
          );

  Future<void> editChecklist(String id, {String? itemId, String? title}) {
    final item = _items(id).doc(itemId);
    final clean = title?.trim();
    if (clean == null && itemId != null) {
      return item.delete().timeout(_writeLimit);
    }
    if (clean == null || clean.isEmpty || clean.length > 160) {
      throw const ProjectRequestException(
        'Judul checklist wajib diisi, maksimal 160 karakter.',
      );
    }
    final data = {'title': clean, 'updatedAt': FieldValue.serverTimestamp()};
    return (itemId == null
            ? item.set({...data, 'done': false})
            : item.update(data))
        .timeout(_writeLimit);
  }

  Future<void> finishChecklist(String id, ChecklistItem item) {
    final event = _db.collection('projectActivities').doc();
    return (_db.batch()
          ..update(_items(id).doc(item.id), {
            'done': true,
            'updatedAt': FieldValue.serverTimestamp(),
            'activityId': event.id,
          })
          ..set(event, {
            'projectId': id,
            'actorId': _account.id,
            'action': 'checklist_done',
            'timestamp': FieldValue.serverTimestamp(),
            'detail': {'itemId': item.id, 'title': item.title},
          }))
        .commit()
        .timeout(_writeLimit);
  }

  Stream<List<ProjectMessage>> watchDiscussion(
    String id, {
    required int limit,
  }) => _db
      .collection('projects/$id/messages')
      .orderBy('timestamp', descending: true)
      .limit(limit)
      .snapshots(includeMetadataChanges: true)
      .confirmed()
      .map(
        (snapshot) => snapshot.docs.reversed.map((doc) {
          final data = doc.data();
          return ProjectMessage(
            data['authorName'] as String,
            data['text'] as String,
            (data['timestamp'] as Timestamp).toDate(),
          );
        }).toList(),
      );

  Future<void> sendMessage(String id, String text) async {
    final clean = text.trim();
    if (clean.isEmpty || clean.length > 1000) {
      throw const ProjectRequestException(
        'Pesan wajib diisi, maksimal 1.000 karakter.',
      );
    }
    final profile =
        (await _db
                .doc('users/${_account.id}')
                .get(const GetOptions(source: Source.server))
                .timeout(_writeLimit))
            .data();
    final message = _db.collection('projects/$id/messages').doc();
    final clock = _db.doc('projects/$id/chatClocks/${_account.id}');
    await (_db.batch()
          ..set(message, {
            'authorId': _account.id,
            'authorName': profile?['name'],
            'text': clean,
            'timestamp': FieldValue.serverTimestamp(),
          })
          ..set(clock, {
            'at': FieldValue.serverTimestamp(),
            'messageId': message.id,
          }))
        .commit()
        .timeout(_writeLimit);
  }

  static const _writeLimit = Duration(seconds: 15);
}

extension ConfirmedQueries on Stream<QuerySnapshot<Map<String, dynamic>>> {
  Stream<QuerySnapshot<Map<String, dynamic>>> confirmed() => where(
    (snapshot) =>
        !snapshot.metadata.isFromCache && !snapshot.metadata.hasPendingWrites,
  );
}
