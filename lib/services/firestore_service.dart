import 'package:cloud_firestore/cloud_firestore.dart';

class FirestoreService {
  final FirebaseFirestore _fs = FirebaseFirestore.instance;

  String dayKey(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return "$y-$m-$day";
  }

  Stream<QuerySnapshot> membersStream() {
    // simple query that always works; we can sort in app if needed
    return _fs.collection("members").snapshots();
  }

  Stream<QuerySnapshot> presenceTodayStream(String todayKey) {
    return _fs
        .collection("presence")
        .where("dayKey", isEqualTo: todayKey)
        .snapshots();
  }

  Future<void> setAttendance({
    required String memberId,
    required String name,
    required bool makeIn,
    String? gathering,
  }) async {
    final day = dayKey(DateTime.now());
    final action = makeIn ? "IN" : "OUT";
    final presenceId = "${day}_$memberId";

    final logRef = _fs.collection("attendance_logs").doc();
    final presenceRef = _fs.collection("presence").doc(presenceId);

    await _fs.runTransaction((tx) async {
      tx.set(logRef, {
        "memberId": memberId,
        "name": name,
        "action": action,
        "dayKey": day,
        if (makeIn) "gathering": gathering ?? "Others",
        "ts": FieldValue.serverTimestamp(),
      });

      tx.set(presenceRef, {
        "memberId": memberId,
        "name": name,
        "dayKey": day,
        "isIn": makeIn,
        "lastAction": action,
        "lastTs": FieldValue.serverTimestamp(),
        if (makeIn) "gathering": gathering ?? "Others",
      }, SetOptions(merge: true));
    });
  }
}
