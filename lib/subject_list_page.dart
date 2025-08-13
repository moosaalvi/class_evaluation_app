import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'teacher_assessment_page.dart';
import 'student_assessment_page.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';


class SubjectListPage extends StatefulWidget {
  final List<Map<String, dynamic>> subjects = [
    {'id': 1, 'name': 'Object-Oriented Programming'},
    {'id': 2, 'name': 'Data-Base System'},
    {'id': 3, 'name': 'Network Security'},
  ];

  final String? role;

  SubjectListPage({Key? key, this.role}) : super(key: key);

  @override
  State<SubjectListPage> createState() => _SubjectListPageState();
}

class _SubjectListPageState extends State<SubjectListPage> {
  File? _profileImage;
  final ImagePicker _picker = ImagePicker();
  List<Map<String, dynamic>> subjects = [];
  bool _loading = true;
  String? _error;
  bool isOnline = true;

  String? _studentName;
  String? _studentRoll;
  String? _teacherName;
  String? _teacherEmail;

  @override
  void initState() {
    super.initState();
    _loadProfileImage();
    // Get route arguments if available
    final args = Get.arguments;
    if (args != null && args is Map) {
      final userRole = args['role'];
      final user = args['user'];
      if (user != null && user is Map) {
        if (userRole == 'student') {
          _studentName = user['name'];
          _studentRoll = user['roll_number'];
        } else {
          _teacherName = user['name'];
          _teacherEmail = user['email'];
        }
      }
    }
    _restoreUserInfo();
    _loadCourses();
  }

  Future<void> _restoreUserInfo() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _studentName = prefs.getString('studentName');
      _studentRoll = prefs.getString('studentRoll');
      _teacherName = prefs.getString('teacherName');
      _teacherEmail = prefs.getString('teacherEmail');
      
      // Load profile image path
      final imagePath = prefs.getString('profileImagePath');
      if (imagePath != null && File(imagePath).existsSync()) {
        _profileImage = File(imagePath);
      }
    });
  }

  Future<void> _saveUserInfo({String? studentName, String? studentRoll, String? teacherName, String? teacherEmail}) async {
    final prefs = await SharedPreferences.getInstance();
    if (studentName != null) prefs.setString('studentName', studentName);
    if (studentRoll != null) prefs.setString('studentRoll', studentRoll);
    if (teacherName != null) prefs.setString('teacherName', teacherName);
    if (teacherEmail != null) prefs.setString('teacherEmail', teacherEmail);
  }

  Future<void> _loadProfileImage() async {
    final prefs = await SharedPreferences.getInstance();
    final imagePath = prefs.getString('profile_image_path');
    if (imagePath != null && File(imagePath).existsSync()) {
      setState(() {
        _profileImage = File(imagePath);
      });
    }
  }

  Future<void> _saveProfileImage(String imagePath) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('profile_image_path', imagePath);
  }

  Future<void> _pickImage() async {
    // Show options for image source
    final ImageSource? source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => Container(
        padding: EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Select Profile Image', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            SizedBox(height: 20),
            ListTile(
              leading: Icon(Icons.photo_library, color: Color(0xFF004AAD)),
              title: Text('Gallery'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
            ListTile(
              leading: Icon(Icons.camera_alt, color: Color(0xFF004AAD)),
              title: Text('Camera'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
          ],
        ),
      ),
    );

    if (source != null) {
      final picked = await _picker.pickImage(
        source: source, 
        imageQuality: 80,
        maxWidth: 400,
        maxHeight: 400,
      );
      
      if (picked != null) {
        setState(() {
          _profileImage = File(picked.path);
        });
        // Save the image path to preferences
        await _saveProfileImage(picked.path);
        
        // Show success message
        Get.snackbar(
          'Success',
          'Profile image updated successfully!',
          backgroundColor: Colors.green,
          colorText: Colors.white,
          snackPosition: SnackPosition.BOTTOM,
        );
      }
    }
  }

  Future<void> _loadCourses() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await http.get(Uri.parse('https://moosaalvi.pythonanywhere.com/api/assessments/courses/'));
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        final List<Map<String, dynamic>> fetchedSubjects = data.map((e) => {
          'id': e['id'],
          'name': e['name'],
        }).toList();
        setState(() {
          subjects = fetchedSubjects;
          _loading = false;
          isOnline = true;
        });
        // Save to SharedPreferences
        final prefs = await SharedPreferences.getInstance();
        prefs.setString('courses', json.encode(fetchedSubjects));
      } else {
        throw Exception('Failed to load courses');
      }
    } catch (e) {
      // Try to load from SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final local = prefs.getString('courses');
      if (local != null) {
        final List<dynamic> data = json.decode(local);
        setState(() {
          subjects = data.map((e) => Map<String, dynamic>.from(e)).toList();
          _loading = false;
          _error = 'No internet, loaded offline.';
          isOnline = false;
        });
      } else {
        setState(() {
          _error = 'Failed to load courses.';
          _loading = false;
          isOnline = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Determine user role: from argument, or fallback to student
    final args = Get.arguments ?? {};
    final String userRole = widget.role ?? (args['role'] ?? 'student');
    final user = args['user'];
    String? studentName = _studentName;
    String? studentRoll = _studentRoll;
    String? teacherName = _teacherName;
    String? teacherEmail = _teacherEmail;
    // On first load, extract from args and save to SharedPreferences
    if (userRole == 'student') {
      final String? apiName = user?['name'] ?? user?['student_name'] ?? '';
      final String? apiRoll = user?['roll_number'] ?? '';
      if ((apiName != null && apiName.isNotEmpty) || (apiRoll != null && apiRoll.isNotEmpty)) {
        studentName = apiName;
        studentRoll = apiRoll;
        _saveUserInfo(studentName: apiName, studentRoll: apiRoll);
      }
    }
    if (userRole == 'teacher') {
      String? apiTeacherName;
      String? apiTeacherEmail;
      if (user?['teacher'] != null) {
        apiTeacherName = user['teacher']['name'] ?? '';
        apiTeacherEmail = user['teacher']['email'] ?? '';
      } else {
        apiTeacherName = user?['name'] ?? user?['teacher_name'] ?? '';
        apiTeacherEmail = user?['email'] ?? '';
      }
      if ((apiTeacherName != null && apiTeacherName.isNotEmpty) || (apiTeacherEmail != null && apiTeacherEmail.isNotEmpty)) {
        teacherName = apiTeacherName;
        teacherEmail = apiTeacherEmail;
        _saveUserInfo(teacherName: apiTeacherName, teacherEmail: apiTeacherEmail);
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Select Subject'),
        actions: [
          IconButton(
            icon: Icon(Icons.logout),
            tooltip: 'Logout',
            onPressed: () async {
              // Clear profile image and other cached data
              final prefs = await SharedPreferences.getInstance();
              await prefs.remove('profileImagePath');
              await prefs.remove('studentName');
              await prefs.remove('studentRoll');
              await prefs.remove('teacherName');
              await prefs.remove('teacherEmail');
              // Clear login state
              await prefs.remove('isLoggedIn');
              await prefs.remove('userRole');
              await prefs.remove('userData');
              Get.offAllNamed('/login');
            },
          ),
        ],
      ),
      body: Column(
        children: [
          if (userRole == 'student' && (studentName != null || studentRoll != null))
            Column(
              children: [
                Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              padding: const EdgeInsets.all(0),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF004AAD), Color(0xFF2196F3), Color(0xFF90CAF9)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.blue.shade100.withOpacity(0.2),
                    blurRadius: 16,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              child: Stack(
                children: [
                  Positioned(
                    right: 0,
                    top: 0,
                    child: Opacity(
                      opacity: 0.12,
                      child: Icon(Icons.school, size: 120, color: Colors.white),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            GestureDetector(
                              onTap: _pickImage,
                              child: CircleAvatar(
                                radius: 28,
                                backgroundColor: Colors.white,
                                backgroundImage: _profileImage != null ? FileImage(_profileImage!) : null,
                                child: _profileImage == null
                                    ? Icon(Icons.person, color: Color(0xFF004AAD), size: 32)
                                    : null,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (studentName != null && studentName.isNotEmpty)
                                    Text(
                                      '$studentName',
                                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: Colors.white),
                                    ),
                                  if (studentRoll != null && studentRoll.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 2.0),
                                      child: Text(
                                        'Roll No: $studentRoll',
                                        style: TextStyle(fontSize: 15, color: Colors.white70),
                                      ),
                                    ),
                                  // Online/Offline status for student
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4.0),
                                    child: Row(
                                      children: [
                                        Icon(
                                          isOnline ? Icons.wifi : Icons.wifi_off,
                                          color: isOnline ? Colors.lightGreen : Colors.orange,
                                          size: 16,
                                        ),
                                        SizedBox(width: 6),
                                        Text(
                                          isOnline ? 'Online' : 'Offline',
                                          style: TextStyle(
                                            color: isOnline ? Colors.lightGreen : Colors.orange,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        Text('Welcome to your dashboard!', style: TextStyle(color: Colors.white.withOpacity(0.95), fontSize: 16)),
                        const SizedBox(height: 8),
                        Text('Tap the profile icon to add/change your picture.', style: TextStyle(color: Colors.white70, fontSize: 13)),
                      ],
                    ),
                  ),
                ],
              ),
                ),
                // Reset password button removed (student)
              ],
            ),
          if (userRole == 'teacher' && (teacherName != null || teacherEmail != null))
            Column(
              children: [
                Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              padding: const EdgeInsets.all(0),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF004AAD), Color(0xFF2196F3), Color(0xFF90CAF9)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.blue.shade100.withOpacity(0.2),
                    blurRadius: 16,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              child: Stack(
                children: [
                  Positioned(
                    right: 0,
                    top: 0,
                    child: Opacity(
                      opacity: 0.12,
                      child: Icon(Icons.school, size: 120, color: Colors.white),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            GestureDetector(
                              onTap: _pickImage,
                              child: CircleAvatar(
                                radius: 28,
                                backgroundColor: Colors.white,
                                backgroundImage: _profileImage != null ? FileImage(_profileImage!) : null,
                                child: _profileImage == null
                                    ? Icon(Icons.person, color: Color(0xFF004AAD), size: 32)
                                    : null,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (teacherName != null && teacherName.isNotEmpty)
                                    Text('$teacherName', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: Colors.white)),
                                  if (teacherEmail != null && teacherEmail.isNotEmpty)
                                    Text('$teacherEmail', style: TextStyle(fontSize: 15, color: Colors.white70)),
                                  // Online/Offline status for teacher
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4.0),
                                    child: Row(
                                      children: [
                                        Icon(
                                          isOnline ? Icons.wifi : Icons.wifi_off,
                                          color: isOnline ? Colors.lightGreen : Colors.orange,
                                          size: 16,
                                        ),
                                        SizedBox(width: 6),
                                        Text(
                                          isOnline ? 'Online' : 'Offline',
                                          style: TextStyle(
                                            color: isOnline ? Colors.lightGreen : Colors.orange,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        Text('Welcome to your dashboard!', style: TextStyle(color: Colors.white.withOpacity(0.95), fontSize: 16)),
                        const SizedBox(height: 8),
                        Text('Tap the profile icon to add/change your picture.', style: TextStyle(color: Colors.white70, fontSize: 13)),
                        const SizedBox(height: 18),
                        
                      ],
                    ),
                  ),
                ],
              ),
                ),
                // Reset password button removed
              ],
            ),
          // Sort subjects by id ascending (1,2,3...)
          Expanded(
            child: _loading
                ? Center(child: CircularProgressIndicator())
                : subjects.isEmpty
                    ? Center(child: Text(_error ?? 'No courses found.'))
                    : (() {
                        final sortedSubjects = [...subjects]..sort((a, b) => (a['id'] as int).compareTo(b['id'] as int));
                        return ListView.builder(
                          itemCount: sortedSubjects.length,
                          itemBuilder: (context, index) {
                            final subject = sortedSubjects[index];
                            return Card(
                              margin: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              child: ListTile(
                                leading: CircleAvatar(child: Text('${subject['id']}')),
                                title: Text(subject['name']),
                                trailing: Icon(Icons.arrow_forward_ios),
                                onTap: () {
                                  if (userRole == 'teacher') {
                                    Get.to(() => AssessmentPage(
                                          subjectId: subject['id'],
                                          subjectName: subject['name'],
                                        ));
                                  } else {
                                    Get.to(() => StudentAssessmentPage(
                                          courseId: subject['id'],
                                          courseName: subject['name'],
                                          studentName: studentName,
                                          studentRoll: studentRoll,
                                        ));
                                  }
                                },
                              ),
                            );
                          },
                        );
                      })(),
          ),
        ],
      ),
    );
  }
}
