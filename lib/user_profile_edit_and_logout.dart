import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

class UserProfilePage extends StatefulWidget {
  const UserProfilePage({super.key});

  @override
  State<UserProfilePage> createState() => _UserProfilePageState();
}

class _UserProfilePageState extends State<UserProfilePage> with SingleTickerProviderStateMixin {
  final _usernameController = TextEditingController();
  XFile? _newProfilePic;
  bool _isLoading = false;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  final user = FirebaseAuth.instance.currentUser;
  String? _profileImageUrl;

  @override
  void initState() {
    super.initState();
    _usernameController.text = user?.displayName ?? '';
    _loadProfileImage();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnimation = CurvedAnimation(parent: _animationController, curve: Curves.easeIn);
    _animationController.forward();
  }

  Future<void> _loadProfileImage() async {
    final prefs = await SharedPreferences.getInstance();
    final savedImageUrl = prefs.getString('profile_image_${user?.uid}');
    if (savedImageUrl != null) {
      setState(() {
        _profileImageUrl = savedImageUrl;
      });
    } else if (user?.photoURL != null) {
      setState(() {
        _profileImageUrl = user!.photoURL;
      });
      // Save Firebase photoURL to SharedPreferences
      await prefs.setString('profile_image_${user?.uid}', user!.photoURL!);
    }
  }

  Future<void> _saveProfileImage(String imageUrl) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('profile_image_${user?.uid}', imageUrl);
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _pickNewImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked != null) {
      setState(() => _newProfilePic = picked);
    }
  }

  Future<void> _updateProfile() async {
    if (_usernameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Username cannot be empty'), backgroundColor: Colors.red),
      );
      return;
    }
    setState(() => _isLoading = true);
    try {
      await user?.updateDisplayName(_usernameController.text.trim());
      if (_newProfilePic != null) {
        final ref = FirebaseStorage.instance.ref('profile_pictures/${user!.uid}.png');
        await ref.putFile(File(_newProfilePic!.path));
        final url = await ref.getDownloadURL();
        await user?.updatePhotoURL(url);
        // Save to SharedPreferences for persistence
        await _saveProfileImage(url);
        setState(() {
          _profileImageUrl = url;
          _newProfilePic = null;
        });
      }
      await user?.reload();
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile Updated!'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _logout() async {
    await FirebaseAuth.instance.signOut();
    if (mounted) Navigator.pushReplacementNamed(context, '/login');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Profile'),
        actions: [
          IconButton(
            onPressed: _logout,
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
          )
        ],
      ),
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                GestureDetector(
                  onTap: _pickNewImage,
                  child: CircleAvatar(
                    radius: 50,
                    backgroundColor: Colors.grey.shade300,
                    backgroundImage: _newProfilePic != null
                        ? FileImage(File(_newProfilePic!.path))
                        : _profileImageUrl != null
                            ? NetworkImage(_profileImageUrl!)
                            : null as ImageProvider?,
                    child: (_newProfilePic == null && _profileImageUrl == null)
                        ? const Icon(Icons.person, size: 50, color: Colors.white)
                        : null,
                  ),
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _usernameController,
                  decoration: InputDecoration(
                    labelText: 'Username',
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 20),
                _isLoading
                    ? const CircularProgressIndicator()
                    : ElevatedButton(
                        onPressed: _updateProfile,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.indigo,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('Update Profile'),
                      ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
