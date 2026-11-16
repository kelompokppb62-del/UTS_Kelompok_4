import 'package:cloud_firestore/cloud_firestore.dart';

class FirestoreServerClock {
  FirestoreServerClock(FirebaseFirestore db, String uid)
    : _document = db.doc('serverClocks/$uid');

  final DocumentReference<Map<String, dynamic>> _document;
  final _elapsed = Stopwatch();
  DateTime? _anchor;
  Future<DateTime>? _syncing;

  /// Server time plus elapsed monotonic time. This is for the UI and transaction
  /// proposals. Firestore Rules use request.time to authorize every write.
  DateTime? get now => _anchor?.add(_elapsed.elapsed);

  Future<DateTime> sync() => _syncing ??= _readClock().whenComplete(() {
    _syncing = null;
  });

  Future<DateTime> _readClock() async {
    await _document
        .set({'at': FieldValue.serverTimestamp()})
        .timeout(const Duration(seconds: 12));
    final snapshot = await _document
        .get(const GetOptions(source: Source.server))
        .timeout(const Duration(seconds: 12));
    final at = snapshot.data()?['at'];
    if (at is! Timestamp || snapshot.metadata.hasPendingWrites) {
      throw StateError('Waktu Firestore belum dikonfirmasi.');
    }
    _anchor = at.toDate().toUtc();
    _elapsed
      ..reset()
      ..start();
    return _anchor!;
  }

  static bool sameJakartaDay(DateTime a, DateTime b) {
    const wib = Duration(hours: 7);
    final left = a.toUtc().add(wib);
    final right = b.toUtc().add(wib);
    return left.year == right.year &&
        left.month == right.month &&
        left.day == right.day;
  }
}
