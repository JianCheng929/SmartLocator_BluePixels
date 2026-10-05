import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseDatabase _database = FirebaseDatabase.instance;

  User? get currentUser => _auth.currentUser;
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  Future<String?> signInWithGoogle() async {
    try {
      // Force sign out first so account picker always appears
      final googleSignIn = GoogleSignIn();
      await googleSignIn.signOut();
      final GoogleSignInAccount? googleUser = await googleSignIn.signIn();
      if (googleUser == null) return 'Sign in cancelled';

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final userCredential =
          await FirebaseAuth.instance.signInWithCredential(credential);
      final user = userCredential.user;

      // Save username to DB if new user
      if (user != null && userCredential.additionalUserInfo?.isNewUser == true) {
        await FirebaseDatabase.instance
            .ref('users/${user.uid}/username')
            .set(user.displayName ?? 'User');
      }
      return null; // success
    } catch (e) {
      return e.toString();
    }
  }

  // ── SIGN UP ──────────────────────────────────────────
  Future<String?> signUp({
    required String username,
    required String email,
    required String password,
  }) async {
    try {
      UserCredential result = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );

      await result.user!.updateDisplayName(username.trim());

      await _database.ref('users/${result.user!.uid}').set({
        'uid': result.user!.uid,
        'username': username.trim(),
        'email': email.trim(),
        'createdAt': ServerValue.timestamp,
        'profilePhoto': '',
      });

      return null;
    } on FirebaseAuthException catch (e) {
      return _handleAuthError(e.code);
    }
  }

  // ── LOGIN ─────────────────────────────────────────────
  Future<String?> login({
    required String email,
    required String password,
  }) async {
    try {
      await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      return null;
    } on FirebaseAuthException catch (e) {
      return _handleAuthError(e.code);
    }
  }

  // ── FORGOT PASSWORD ───────────────────────────────────
  Future<String?> sendPasswordReset(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
      return null;
    } on FirebaseAuthException catch (e) {
      return _handleAuthError(e.code);
    }
  }

  // ── SIGN OUT ──────────────────────────────────────────
  Future<void> signOut() async {
    await _auth.signOut();
  }

  // ── GET USER PROFILE ──────────────────────────────────
  Future<Map<String, dynamic>?> getUserProfile() async {
    try {
      final snapshot = await _database
          .ref('users/${currentUser!.uid}')
          .get();
      if (snapshot.exists) {
        return Map<String, dynamic>.from(snapshot.value as Map);
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  // ── ERROR MESSAGES ────────────────────────────────────
  String _handleAuthError(String code) {
    switch (code) {
      case 'email-already-in-use':
        return 'This email is already registered.';
      case 'invalid-email':
        return 'Please enter a valid email.';
      case 'weak-password':
        return 'Password must be at least 6 characters.';
      case 'user-not-found':
        return 'No account found with this email.';
      case 'wrong-password':
        return 'Incorrect password. Try again.';
      case 'too-many-requests':
        return 'Too many attempts. Please wait and try again.';
      default:
        return 'Something went wrong. Please try again.';
    }
  }
}