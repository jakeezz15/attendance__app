import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../services/firestore_service.dart';
import '../services/admin_auth_service.dart';

import 'admin_login_page.dart';
import 'attendance_logs_page.dart';
import 'import_members_page.dart';

class AttendancePage extends StatefulWidget {
  const AttendancePage({super.key});

  @override
  State<AttendancePage> createState() => _AttendancePageState();
}

class _AttendancePageState extends State<AttendancePage> {
  final _service = FirestoreService();
  late Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _membersFuture;

  String _search = "";
  String? passgathering;

  @override
  void initState() {
    super.initState();
    _membersFuture = _service.getMembersCached();
  }

  Future<void> _refreshMembers() async {
    setState(() {
      _membersFuture = _service.getMembersCached();
    });
  }

  // ✅ Purpose dialog (IN only)
  Future<String?> _askPurposeOfVisit(BuildContext context) async {
    const options = ["PM", "WS", "TG", "Others"];
    String selected = options.first;

    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text("Purpose of Visit?"),
            content: DropdownButtonFormField<String>(
              value: selected,
              items: options
                  .map((o) => DropdownMenuItem(value: o, child: Text(o)))
                  .toList(),
              onChanged: (v) {
                if (v == null) return;
                setState(() => selected = v);
              },
              decoration: const InputDecoration(border: OutlineInputBorder()),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, null),
                child: const Text("Cancel"),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, selected),
                child: const Text("OK"),
              ),
            ],
          );
        },
      ),
    );
  }

  // ✅ Sort groups numerically when group is stored as "1", "2", "10"
  List<String> _sortGroupKeys(Set<String> keys) {
    final list = keys.toList();
    list.sort((a, b) {
      if (a == "Ungrouped") return 1;
      if (b == "Ungrouped") return -1;

      final ai = int.tryParse(a);
      final bi = int.tryParse(b);

      if (ai != null && bi != null) return ai.compareTo(bi);
      if (ai != null) return -1;
      if (bi != null) return 1;
      return a.compareTo(b);
    });
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final todayKey = _service.dayKey(DateTime.now());

    return Scaffold(
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _service.presenceTodayStream(todayKey),
        builder: (context, presSnap) {
          // memberId -> isIn
          final Map<String, bool> isInByMember = {};

          int headcount = 0;

          if (presSnap.hasData) {
            for (final doc in presSnap.data!.docs) {
              final data = doc.data();
              final memberId = data["memberId"] as String?;
              final isIn = data["isIn"] as bool? ?? false;

              if (memberId != null) {
                isInByMember[memberId] = isIn;
                if (isIn) headcount++;
              }
            }
          }

          return FutureBuilder<
            List<QueryDocumentSnapshot<Map<String, dynamic>>>
          >(
            future: _membersFuture,
            builder: (context, memSnap) {
              if (memSnap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (memSnap.hasError) {
                return Center(child: Text("Error: ${memSnap.error}"));
              }

              final allMembers = memSnap.data ?? [];

              // Search filter (name)
              final q = _search.trim().toLowerCase();
              final filtered = allMembers.where((doc) {
                final data = doc.data();
                final name = (data["name"] as String? ?? "").toLowerCase();
                return q.isEmpty || name.contains(q);
              }).toList();

              // Grouping
              final Map<
                String,
                List<QueryDocumentSnapshot<Map<String, dynamic>>>
              >
              grouped = {};
              for (final doc in filtered) {
                final data = doc.data();
                final g = (data["group"] as String?)?.trim();
                final key = (g == null || g.isEmpty) ? "Ungrouped" : g;
                grouped.putIfAbsent(key, () => []).add(doc);
              }

              final groupKeys = _sortGroupKeys(grouped.keys.toSet());

              // Sort members within each group by name
              for (final k in groupKeys) {
                grouped[k]!.sort((a, b) {
                  final an = (a.data()["name"] as String?) ?? "";
                  final bn = (b.data()["name"] as String?) ?? "";
                  return an.compareTo(bn);
                });
              }

              return NestedScrollView(
                headerSliverBuilder: (context, innerBoxIsScrolled) {
                  return [
                    SliverAppBar(
                      pinned: true,
                      title: const Text("Attendance"),
                      actions: [
                        IconButton(
                          icon: const Icon(Icons.refresh),
                          tooltip: "Refresh members",
                          onPressed: _refreshMembers,
                        ),
                        IconButton(
                          icon: const Icon(Icons.person_add_alt_1),
                          tooltip: "Import Members",
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ImportMembersPage(),
                              ),
                            );
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.list_alt),
                          tooltip: "View Logs",
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const AttendanceLogsPage(),
                              ),
                            );
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.logout),
                          tooltip: "Logout",
                          onPressed: () async {
                            final confirm = await showDialog<bool>(
                              context: context,
                              builder: (_) => AlertDialog(
                                title: const Text("Logout"),
                                content: const Text(
                                  "Do you want to logout admin?",
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.pop(context, false),
                                    child: const Text("Cancel"),
                                  ),
                                  ElevatedButton(
                                    onPressed: () =>
                                        Navigator.pop(context, true),
                                    child: const Text("Logout"),
                                  ),
                                ],
                              ),
                            );

                            if (confirm == true) {
                              await AdminAuthService.logout();
                              if (!context.mounted) return;

                              Navigator.pushAndRemoveUntil(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const AdminLoginPage(),
                                ),
                                (route) => false,
                              );
                            }
                          },
                        ),
                      ],
                      bottom: PreferredSize(
                        preferredSize: const Size.fromHeight(108),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                          child: Column(
                            children: [
                              // ✅ Headcount row
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 10,
                                  horizontal: 12,
                                ),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(14),
                                  color: Theme.of(context).colorScheme.surface,
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.people),
                                    const SizedBox(width: 8),
                                    Text(
                                      "People Inside: $headcount",
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 10),

                              // ✅ Search bar (still pinned)
                              TextField(
                                decoration: InputDecoration(
                                  hintText: "Search name...",
                                  prefixIcon: const Icon(Icons.search),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  isDense: true,
                                  filled: true,
                                ),
                                onChanged: (v) => setState(() => _search = v),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ];
                },
                body: ListView(
                  padding: const EdgeInsets.all(12),
                  children: groupKeys.isEmpty
                      ? const [
                          Padding(
                            padding: EdgeInsets.all(24),
                            child: Center(child: Text("No members found.")),
                          ),
                        ]
                      : groupKeys.map((groupName) {
                          final members = grouped[groupName] ?? const [];
                          final headerText = groupName == "Ungrouped"
                              ? "Ungrouped"
                              : "Group $groupName";

                          return _GroupSection(
                            title: headerText,
                            members: members,
                            isInByMember: isInByMember,
                            onTapMember: (memberId, name, isIn) async {
                              // IN -> ask purpose
                              if (!isIn) {
                                final gathering = await _askPurposeOfVisit(
                                  context,
                                );
                                if (gathering == null) return;

                                passgathering = gathering;

                                await _service.setAttendance(
                                  memberId: memberId,
                                  name: name,
                                  makeIn: true,
                                  gathering: gathering,
                                );
                                return;
                              }

                              // OUT -> confirm only
                              final confirm = await showDialog<bool>(
                                context: context,
                                builder: (_) => AlertDialog(
                                  title: const Text("Logout?"),
                                  content: Text("Do you want to logout $name?"),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(context, false),
                                      child: const Text("No"),
                                    ),
                                    ElevatedButton(
                                      onPressed: () =>
                                          Navigator.pop(context, true),
                                      child: const Text("Yes"),
                                    ),
                                  ],
                                ),
                              );

                              if (confirm == true) {
                                await _service.setAttendance(
                                  memberId: memberId,
                                  name: name,
                                  makeIn: false,
                                  gathering: passgathering,
                                );
                              }
                            },
                          );
                        }).toList(),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _GroupSection extends StatelessWidget {
  final String title;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> members;
  final Map<String, bool> isInByMember;
  final Future<void> Function(String memberId, String name, bool isIn)
  onTapMember;

  const _GroupSection({
    required this.title,
    required this.members,
    required this.isInByMember,
    required this.onTapMember,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ),

        // ✅ Responsive grid: portrait 1, landscape phone 2, tablet 3
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;

            int crossAxisCount;
            double childAspectRatio;

            if (width >= 900) {
              crossAxisCount = 3;
              childAspectRatio = 2.8;
            } else if (width >= 600) {
              crossAxisCount = 2;
              childAspectRatio = 3.2;
            } else {
              crossAxisCount = 1;
              childAspectRatio = 8;
            }

            return GridView.builder(
              itemCount: members.length,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                childAspectRatio: childAspectRatio,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              itemBuilder: (context, i) {
                final doc = members[i];
                final data = doc.data();
                final memberId = doc.id;
                final name = (data["name"] as String?) ?? "No Name";
                final isIn = isInByMember[memberId] ?? false;

                return ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isIn ? Colors.green : null,
                    foregroundColor: isIn ? Colors.white : null,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: () => onTapMember(memberId, name, isIn),
                  child: Text(
                    name,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                );
              },
            );
          },
        ),

        const SizedBox(height: 20),
      ],
    );
  }
}
