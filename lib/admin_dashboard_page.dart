import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class AdminDashboardPage extends StatefulWidget {
  const AdminDashboardPage({super.key});

  @override
  State<AdminDashboardPage> createState() => _AdminDashboardPageState();
}

class _AdminDashboardPageState extends State<AdminDashboardPage> {
  final CollectionReference usersCollection =
      FirebaseFirestore.instance.collection('users');

  Future<void> approveTeacher(String userId) async {
    await usersCollection.doc(userId).update({'isApproved': true});
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Teacher Approved')),
    );
  }

  Future<void> rejectTeacher(String userId) async {
    await usersCollection.doc(userId).delete();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Teacher Rejected & Removed')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Panel - Pending Teachers'),
        backgroundColor: Colors.indigo,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: usersCollection
            .where('role', isEqualTo: 'teacher')
            .where('isApproved', isEqualTo: false)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text('Error loading data.'));
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final teacherDocs = snapshot.data!.docs;

          if (teacherDocs.isEmpty) {
            return const Center(child: Text('No pending teacher requests.'));
          }

          return ListView.builder(
            itemCount: teacherDocs.length,
            itemBuilder: (context, index) {
              final teacher = teacherDocs[index];
              return Card(
                margin: const EdgeInsets.all(8),
                child: ListTile(
                  title: Text(teacher['username']),
                  subtitle: Text(teacher['email']),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.check, color: Colors.green),
                        onPressed: () => approveTeacher(teacher.id),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.red),
                        onPressed: () => rejectTeacher(teacher.id),
                      ),
                    ],
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
