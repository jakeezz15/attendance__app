import 'package:attendance_app/pages/attendance_logs_page.dart';
import 'package:attendance_app/pages/import_members_page.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/firestore_service.dart';
import '../services/admin_auth_service.dart';
import 'admin_login_page.dart';

class AttendancePage extends StatefulWidget {
  const AttendancePage({super.key});

  @override
  State<AttendancePage> createState() => _AttendancePageState();
}

class _SearchBarHeader extends StatelessWidget {
  final ValueChanged<String> onChanged;
  final String initialValue;

  const _SearchBarHeader({required this.onChanged, required this.initialValue});

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: TextField(
          controller: TextEditingController(text: initialValue),
          decoration: InputDecoration(
            hintText: "Search name...",
            prefixIcon: const Icon(Icons.search),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
            isDense: true,
          ),
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class _AttendancePageState extends State<AttendancePage> {
  final _service = FirestoreService();
  String _search = "";

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

  @override
  Widget build(BuildContext context) {
    final todayKey = _service.dayKey(DateTime.now());

    return Scaffold(
      body: StreamBuilder<QuerySnapshot>(
        stream: _service.presenceTodayStream(todayKey),
        builder: (context, presSnap) {
          final Map<String, bool> isInByMember = {};

          if (presSnap.hasData) {
            for (final doc in presSnap.data!.docs) {
              final data = doc.data() as Map<String, dynamic>;
              final memberId = data["memberId"] as String?;
              final isIn = data["isIn"] as bool?;
              if (memberId != null) isInByMember[memberId] = isIn ?? false;
            }
          }

          return StreamBuilder<QuerySnapshot>(
            stream: _service.membersStream(),
            builder: (context, memSnap) {
              if (memSnap.hasError) {
                return Center(child: Text("Error: ${memSnap.error}"));
              }
              if (!memSnap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              // 1) Filter active
              final all = memSnap.data!.docs.where((d) {
                final data = d.data() as Map<String, dynamic>;
                return (data["active"] as bool?) ?? true;
              }).toList();

              // 2) Filter by search text
              final query = _search.trim().toLowerCase();
              final filtered = all.where((d) {
                final data = d.data() as Map<String, dynamic>;
                final name = (data["name"] as String? ?? "").toLowerCase();
                return query.isEmpty || name.contains(query);
              }).toList();

              // 3) Group by "group" field
              final Map<String, List<QueryDocumentSnapshot>> grouped = {};
              for (final doc in filtered) {
                final data = doc.data() as Map<String, dynamic>;
                final groupName = (data["group"] as String?)?.trim();
                final key = (groupName == null || groupName.isEmpty)
                    ? "Ungrouped"
                    : groupName;

                grouped.putIfAbsent(key, () => []).add(doc);
              }

              // 4) Sort groups by name
              final groupKeys = grouped.keys.toList()
                ..sort((a, b) {
                  if (a == "Ungrouped") return 1; // always last
                  if (b == "Ungrouped") return -1;

                  final int? ai = int.tryParse(a);
                  final int? bi = int.tryParse(b);

                  // If both are valid numbers → numeric sort
                  if (ai != null && bi != null) {
                    return ai.compareTo(bi);
                  }

                  // If only one is numeric → numeric comes first
                  if (ai != null) return -1;
                  if (bi != null) return 1;

                  // Fallback: normal string sort
                  return a.compareTo(b);
                });

              // 5) Sort members in each group by name
              for (final key in groupKeys) {
                grouped[key]!.sort((a, b) {
                  final an =
                      (((a.data() as Map<String, dynamic>)["name"]) ?? "")
                          as String;
                  final bn =
                      (((b.data() as Map<String, dynamic>)["name"]) ?? "")
                          as String;
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
                                builder: (_) => AttendanceLogsPage(),
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
                                (route) => false, // clears back stack
                              );
                            }
                          },
                        ),
                      ],
                      bottom: PreferredSize(
                        preferredSize: const Size.fromHeight(64),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                          child: TextField(
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
                          final members =
                              grouped[groupName] ??
                              const <QueryDocumentSnapshot>[];
                          return _GroupSection(
                            title: "Group $groupName",
                            members: members,
                            isInByMember: isInByMember,
                            onTapMember: (memberId, name, isIn) async {
                              if (!isIn) {
                                final gathering = await _askPurposeOfVisit(
                                  context,
                                );
                                if (gathering == null) return; // cancelled

                                await _service.setAttendance(
                                  memberId: memberId,
                                  name: name,
                                  makeIn: true,
                                  gathering: gathering, // ✅ store purpose
                                );
                                return;
                              }

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

class _PinnedHeaderDelegate extends SliverPersistentHeaderDelegate {
  final double height;
  final Widget child;

  _PinnedHeaderDelegate({required this.height, required this.child});

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return child;
  }

  @override
  bool shouldRebuild(covariant _PinnedHeaderDelegate oldDelegate) {
    return oldDelegate.height != height || oldDelegate.child != child;
  }
}

class _GroupSection extends StatelessWidget {
  final String title;
  final List<QueryDocumentSnapshot> members;
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
        // Group header
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ),

        // Grid for this group (responsive)
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;

            // Decide columns based on width
            int crossAxisCount;
            double childAspectRatio;

            if (width >= 900) {
              // Tablets / large screens (landscape)
              crossAxisCount = 3;
              childAspectRatio = 2.8;
            } else if (width >= 600) {
              // Phones landscape
              crossAxisCount = 2;
              childAspectRatio = 3.2;
            } else {
              // Portrait phones
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
                final data = doc.data() as Map<String, dynamic>;
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
