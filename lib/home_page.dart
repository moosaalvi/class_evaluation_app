import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'subject_list_page.dart';
import 'user_profile_edit_and_logout.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  bool? isTeacher;
  bool isAdmin = false;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(parent: _controller, curve: Curves.easeInOut);
    _controller.forward();
    checkUserRole();
  }

  Future<void> checkUserRole() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      if (doc.exists) {
        setState(() {
          isTeacher = doc['role'] == 'teacher';
          isAdmin = doc['role'] == 'admin';
          isLoading = false;
        });
      } else {
        setState(() {
          isTeacher = false;
          isAdmin = false;
          isLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget buildHeader() {
    return Column(
      children: [
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'Department of CS',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.indigo,
              ),
            ),
            const SizedBox(width: 8),
            Image.asset(
              'assets/cs_logo.PNG',
              height: 40,
            ),
          ],
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget buildTeacherView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("Your Subjects", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
        const SizedBox(height: 10),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          children: List.generate(4, (index) {
            return GestureDetector(
              onTap: () {
                Navigator.pushNamed(context, '/subject${index + 1}');
              },
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.indigo.shade100,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(color: Colors.indigo.shade300, blurRadius: 6, offset: const Offset(2, 4))
                  ],
                ),
                padding: const EdgeInsets.all(16),
                child: Center(
                  child: Text(
                    'Subject ${index + 1}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            );
          }),
        ),
      ],
    );
  }

  Widget buildStudentView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("Courses", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
        const SizedBox(height: 10),
        GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => SubjectListPage()),
            );
          },
          child: Container(
            decoration: BoxDecoration(
              color: Colors.indigo.shade100,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(color: Colors.indigo.shade300, blurRadius: 6, offset: const Offset(2, 4))
              ],
            ),
            padding: const EdgeInsets.all(24),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                Icon(Icons.menu_book, size: 28, color: Colors.indigo),
                SizedBox(width: 12),
                Text('View All Courses', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget buildAdminView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("Pending Approvals", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
        const SizedBox(height: 10),
        ElevatedButton(
          onPressed: () {
            Navigator.pushNamed(context, '/adminRequests');
          },
          child: const Text('Manage Requests'),
        ),
      ],
    );
  }

  Widget buildFooter() {
    return BottomNavigationBar(
      selectedItemColor: Colors.indigo,
      unselectedItemColor: Colors.grey,
      items: const [
        BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
        BottomNavigationBarItem(icon: Icon(Icons.assignment), label: 'Evaluations'),
        BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
      ],
      currentIndex: 0,
      onTap: (index) {
        if (index == 2) {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => UserProfilePage()),
          );
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      bottomNavigationBar: buildFooter(),
      body: SafeArea(
        child: isLoading
            ? const Center(child: CircularProgressIndicator())
            : FadeTransition(
                opacity: _fadeAnimation,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      buildHeader(),
                      if (isAdmin)
                        buildAdminView()
                      else if (isTeacher == true)
                        buildTeacherView()
                      else
                        buildStudentView(),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}
