import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';

class FirebaseService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;

  // Sign up with email, password, username, and optional profile picture
  Future<String?> signUp({
    required String email,
    required String password,
    required String username,
    XFile? profilePicture,
  }) async {
    try {
      UserCredential userCredential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      User? user = userCredential.user;
      if (user != null) {
        // Update user profile with username
        await user.updateDisplayName(username);
        // Upload profile picture if provided
        if (profilePicture != null) {
          String fileName = 'profile_pictures/${user.uid}.png';
          await _storage.ref(fileName).putFile(File(profilePicture.path));
          String photoUrl = await _storage.ref(fileName).getDownloadURL();
          await user.updatePhotoURL(photoUrl);
        }
        // Send email verification
        await user.sendEmailVerification();
        return null; // Success
      }
      return 'Failed to create user';
    } catch (e) {
      return e.toString();
    }
  }

  // Log in with email and password
  Future<String?> logIn({
    required String email,
    required String password,
  }) async {
    try {
      await _auth.signInWithEmailAndPassword(email: email, password: password);
      return null; // Success
    } catch (e) {
      return e.toString();
    }
  }

  // Sign out
  Future<void> signOut() async {
    await _auth.signOut();
  }
}