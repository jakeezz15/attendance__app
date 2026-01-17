import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AdminAuthService {
  static final _auth = FirebaseAuth.instance;
  static final _fs = FirebaseFirestore.instance;

  static Future<bool> login(String email, String password) async {
    try {
      final cred = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );

      final uid = cred.user!.uid;

      final adminDoc = await _fs.collection('admin_users').doc(uid).get();

      final isActiveAdmin =
          adminDoc.exists && (adminDoc.data()?['active'] == true);

      if (!isActiveAdmin) {
        await _auth.signOut();
      }

      return isActiveAdmin;
    } on FirebaseAuthException catch (e) {
      // IMPORTANT: print the real reason in Debug Console
      // e.code examples: user-not-found, wrong-password, invalid-email
      print("FirebaseAuthException: ${e.code} ${e.message}");
      rethrow;
    } catch (e) {
      print("Login error: $e");
      rethrow;
    }
  }

  static Future<void> logout() async => _auth.signOut();
}
