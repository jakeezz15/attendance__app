import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'dart:io';
import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../utils/csv_downloader.dart';

class AttendanceLogsPage extends StatefulWidget {
  const AttendanceLogsPage({super.key});

  @override
  State<AttendanceLogsPage> createState() => _AttendanceLogsPageState();
}

class _AttendanceLogsPageState extends State<AttendanceLogsPage> {
  Future<void> _exportCsv() async {
    final dayKey = _dayKey(_selectedDate);

    final snap = await FirebaseFirestore.instance
        .collection("attendance_logs")
        .where("dayKey", isEqualTo: dayKey)
        .get();

    final docs = snap.docs.toList()
      ..sort((a, b) {
        final at = (a.data()["ts"] as Timestamp?)?.toDate();
        final bt = (b.data()["ts"] as Timestamp?)?.toDate();
        return (bt ?? DateTime(1970)).compareTo(at ?? DateTime(1970));
      });

    if (docs.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No records to export for this day.")),
      );
      return;
    }

    final rows = <List<dynamic>>[
      ["Date", "Time", "Name", "Gathering", "Action", "MemberId"],
    ];

    for (final d in docs) {
      final data = d.data();
      final ts = (data["ts"] as Timestamp?)?.toDate();

      rows.add([
        ts == null ? dayKey : DateFormat("yyyy-MM-dd").format(ts),
        ts == null ? "" : DateFormat("HH:mm:ss").format(ts),
        data["name"] ?? "",
        data["gathering"] ?? "Others",
        data["action"] ?? "",
        data["memberId"] ?? "",
      ]);
    }

    final csvText = const ListToCsvConverter().convert(rows);
    final fileName = "attendance_$dayKey.csv";

    // 🌐 WEB → trigger browser download
    if (kIsWeb) {
      _downloadCsvWeb(csvText, fileName);
      return;
    }

    // 📱 MOBILE → save + share
    final dir = await getApplicationDocumentsDirectory();
    final file = File("${dir.path}/$fileName");
    await file.writeAsString(csvText, flush: true);

    await Share.shareXFiles([
      XFile(file.path),
    ], text: "Attendance export for $dayKey");
  }

  void _downloadCsvWeb(String csv, String fileName) {
    // ignore: avoid_web_libraries_in_flutter

    if (kIsWeb) {
      downloadCsv("Attendance Log", "atendance_log.csv");
    }
    return;
  }

  DateTime _selectedDate = DateTime.now();

  String _dayKey(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return "$y-$m-$day";
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dayKey = _dayKey(_selectedDate);
    final titleDate = DateFormat("MMM d, yyyy").format(_selectedDate);

    final logsQuery = FirebaseFirestore.instance
        .collection("attendance_logs")
        .where("dayKey", isEqualTo: dayKey)
        .orderBy("ts", descending: true);

    return Scaffold(
      appBar: AppBar(
        title: Text("Logs • $titleDate"),
        actions: [
          IconButton(
            icon: const Icon(Icons.download),
            tooltip: "Export CSV",
            onPressed: _exportCsv,
          ),

          IconButton(
            icon: const Icon(Icons.calendar_month),
            tooltip: "Pick date",
            onPressed: _pickDate,
          ),
          IconButton(
            icon: const Icon(Icons.today),
            tooltip: "Go to today",
            onPressed: () => setState(() => _selectedDate = DateTime.now()),
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: logsQuery.snapshots(),
        builder: (context, snap) {
          if (snap.hasError) {
            // If Firestore asks for an index, the error will appear here.
            return Center(child: Text("Error: ${snap.error}"));
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final logs = snap.data!.docs;
          if (logs.isEmpty) {
            return Center(child: Text("No records for $titleDate."));
          }

          return ListView.separated(
            itemCount: logs.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final data = logs[i].data() as Map<String, dynamic>;

              final name = (data["name"] as String?) ?? "Unknown";
              final action = (data["action"] as String?) ?? "-";
              final ts = data["ts"] as Timestamp?;
              final dt = ts?.toDate();
              final ga = data["gathering"] as String?;

              final timeStr = dt == null
                  ? "-"
                  : DateFormat("hh:mm a").format(dt);
              final isIn = action == "IN";

              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: isIn ? Colors.green : Colors.red,
                  child: Icon(
                    isIn ? Icons.login : Icons.logout,
                    color: Colors.white,
                  ),
                ),
                title: Text(
                  name,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text("$timeStr • Purpose: ${ga ?? 'Logged out'}"),
                trailing: Text(
                  action,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: isIn ? Colors.green : Colors.red,
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
