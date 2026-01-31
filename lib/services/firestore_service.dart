import 'package:cloud_firestore/cloud_firestore.dart';

class FirestoreService {
  final FirebaseFirestore _fs = FirebaseFirestore.instance;

  String dayKey(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return "$y-$m-$day";
  }

  /// ✅ Presence stream (small + realtime)
  Stream<QuerySnapshot<Map<String, dynamic>>> presenceTodayStream(
    String todayKey,
  ) {
    return _fs
        .collection("presence")
        .where("dayKey", isEqualTo: todayKey)
        .snapshots();
  }

  /// ✅ Members: cache-first, one-time load (reduces reads a lot)
  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
  getMembersCached() async {
    final query = _fs.collection("members").where("active", isEqualTo: true);

    // 1) Try cache first
    try {
      final cached = await query.get(const GetOptions(source: Source.cache));
      if (cached.docs.isNotEmpty) return cached.docs;
    } catch (_) {
      // ignore cache errors
    }

    // 2) Fallback to server (also updates cache)
    final server = await query.get(const GetOptions(source: Source.server));
    return server.docs;
  }

  /// ✅ Attendance write (gathering only for IN)
  Future<void> setAttendance({
    required String memberId,
    required String name,
    required bool makeIn,
    String? gathering, // only for IN
  }) async {
    final day = dayKey(DateTime.now());
    final action = makeIn ? "IN" : "OUT";

    // Presence is per day (green status). If you later want per gathering, tell me.
    final presenceId = "${day}_$memberId";

    final logRef = _fs.collection("attendance_logs").doc();
    final presenceRef = _fs.collection("presence").doc(presenceId);

    await _fs.runTransaction((tx) async {
      // Always append a log
      tx.set(logRef, {
        "memberId": memberId,
        "name": name,
        "action": action,
        "dayKey": day,
        "ts": FieldValue.serverTimestamp(),
        if (makeIn) "gathering": gathering ?? "Others",
      });

      // Update today's state
      tx.set(presenceRef, {
        "memberId": memberId,
        "name": name,
        "dayKey": day,
        "isIn": makeIn,
        "lastAction": action,
        "lastTs": FieldValue.serverTimestamp(),
        "gathering": gathering,
      }, SetOptions(merge: true));
    });
  }
}
