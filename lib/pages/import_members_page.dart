import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

class ImportMembersPage extends StatefulWidget {
  const ImportMembersPage({super.key});

  @override
  State<ImportMembersPage> createState() => _ImportMembersPageState();
}

class _ImportMembersPageState extends State<ImportMembersPage> {
  bool _loading = false;
  String? _status;
  List<Map<String, dynamic>> _rows = [];

  Future<void> _pickAndParseXlsx() async {
    setState(() {
      _loading = true;
      _status = "Picking file…";
      _rows = [];
    });

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
        withData: true, // IMPORTANT for Web (gives bytes)
      );

      if (result == null || result.files.isEmpty) {
        setState(() {
          _loading = false;
          _status = "No file selected.";
        });
        return;
      }

      final file = result.files.first;
      final bytes = file.bytes;
      if (bytes == null) {
        setState(() {
          _loading = false;
          _status = "Could not read file bytes.";
        });
        return;
      }

      setState(() => _status = "Reading Excel…");
      final parsed = _parseExcel(bytes);

      setState(() {
        _rows = parsed;
        _loading = false;
        _status = "Loaded ${parsed.length} members.";
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _status = "Error: $e";
      });
    }
  }

  List<Map<String, dynamic>> _parseExcel(Uint8List bytes) {
    final excel = Excel.decodeBytes(bytes);
    if (excel.tables.isEmpty) return [];

    // Use first sheet
    final sheetName = excel.tables.keys.first;
    final sheet = excel.tables[sheetName]!;
    if (sheet.rows.isEmpty) return [];

    // Expect header row in row 0
    final headerRow = sheet.rows.first;
    final headers = headerRow
        .map((c) => (c?.value?.toString() ?? "").trim().toLowerCase())
        .toList();

    int idxOf(String key) => headers.indexOf(key);

    final nameIdx = idxOf("name");
    if (nameIdx == -1) {
      throw Exception("Excel must have a header column named 'name'.");
    }

    final groupIdx = idxOf("group");
    final activeIdx = idxOf("active");
    final genderIdx = idxOf("gender");

    final out = <Map<String, dynamic>>[];

    for (int r = 1; r < sheet.rows.length; r++) {
      final row = sheet.rows[r];

      String cellStr(int i) => (i >= 0 && i < row.length)
          ? (row[i]?.value?.toString() ?? "").trim()
          : "";

      final name = cellStr(nameIdx);
      if (name.isEmpty) continue;

      final group = groupIdx == -1 ? "" : cellStr(groupIdx);
      final gender = genderIdx == -1 ? "" : cellStr(genderIdx);

      bool active = true;
      if (activeIdx != -1) {
        final raw = cellStr(activeIdx).toLowerCase();
        if (raw.isEmpty) {
          active = true;
        } else if (raw == "true" || raw == "yes" || raw == "1") {
          active = true;
        } else if (raw == "false" || raw == "no" || raw == "0") {
          active = false;
        } else {
          // unknown -> default true
          active = true;
        }
      }

      out.add({
        "name": name,
        "group": group,
        "gender": gender,
        "active": active,
      });
    }

    return out;
  }

  Future<void> _uploadToFirestore() async {
    if (_rows.isEmpty) {
      setState(() => _status = "No rows to upload.");
      return;
    }

    setState(() {
      _loading = true;
      _status = "Uploading…";
    });

    try {
      final fs = FirebaseFirestore.instance;
      final col = fs.collection("members");

      // Firestore batch limit is 500 writes per batch
      const batchLimit = 450;
      int uploaded = 0;

      for (int i = 0; i < _rows.length; i += batchLimit) {
        final batch = fs.batch();
        final chunk = _rows.skip(i).take(batchLimit);

        for (final m in chunk) {
          // Use auto-id docs (simple). If you want name-based IDs, tell me.
          final docRef = col.doc();
          batch.set(docRef, {...m, "createdAt": FieldValue.serverTimestamp()});
          uploaded++;
        }

        await batch.commit();
      }

      setState(() {
        _loading = false;
        _status = "Upload complete ✅ ($uploaded members)";
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _status = "Upload error: $e";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Import Members (Excel)")),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _loading ? null : _pickAndParseXlsx,
                    icon: const Icon(Icons.upload_file),
                    label: const Text("Select .xlsx"),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: (_loading || _rows.isEmpty)
                        ? null
                        : _uploadToFirestore,
                    icon: const Icon(Icons.cloud_upload),
                    label: const Text("Upload to Firestore"),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_status != null) Text(_status!),
            const SizedBox(height: 12),
            if (_loading) const LinearProgressIndicator(),
            const SizedBox(height: 12),

            // Preview
            Expanded(
              child: _rows.isEmpty
                  ? const Center(child: Text("No data loaded yet."))
                  : ListView.separated(
                      itemCount: _rows.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final m = _rows[i];
                        return ListTile(
                          title: Text(m["name"] ?? ""),
                          subtitle: Text(
                            "group: ${m["group"] ?? ""} • active: ${m["active"]} • gender: ${m["gender"] ?? ""}",
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
