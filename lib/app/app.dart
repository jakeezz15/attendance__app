import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../pages/admin_login_page.dart';
import '../pages/attendance_page.dart';

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Attendance App',
      home: FirebaseAuth.instance.currentUser == null
          ? const AdminLoginPage()
          : const AttendancePage(),
    );
  }
}
