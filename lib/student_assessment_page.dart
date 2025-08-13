import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:intl/intl.dart';
import 'student_evaluation_page.dart';

class StudentAssessmentPage extends StatefulWidget {
  final int courseId;
  final String courseName;
  final String? studentName;
  final String? studentRoll;

  const StudentAssessmentPage({
    super.key,
    required this.courseId,
    required this.courseName,
    this.studentName,
    this.studentRoll,
  });

  @override
  State<StudentAssessmentPage> createState() => _StudentAssessmentPageState();
}

class _StudentAssessmentPageState extends State<StudentAssessmentPage> {
  List assessments = [];
  bool isOnline = true;

  @override
  void initState() {
    super.initState();
    _loadCachedData();
    fetchAssessments();
  }

  Future<void> _loadCachedData() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? cached = prefs.getString('student_assessments_${widget.courseId}');
    if (cached != null) {
      setState(() {
        assessments = jsonDecode(cached);
      });
    }
  }

  Future<void> _cacheData(List data) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('student_assessments_${widget.courseId}', jsonEncode(data));
  }

  Future<void> fetchAssessments() async {
    final url = Uri.parse("https://moosaalvi.pythonanywhere.com/api/assessments/?course_id=${widget.courseId}");
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          assessments = data;
          isOnline = true;
        });
        await _cacheData(data);
      } else {
        setState(() {
          isOnline = false;
        });
      }
    } catch (e) {
      // Handle offline silently
      setState(() {
        isOnline = false;
      });
    }
  }

  String formatDateTime(String? dateTimeStr) {
    if (dateTimeStr == null) return "N/A";
    final dt = DateTime.tryParse(dateTimeStr);
    if (dt == null) return "N/A";
    return DateFormat('dd MMM yyyy - hh:mm a').format(dt);
  }

  bool isAssessmentExpired(String? endTimeStr) {
    final end = DateTime.tryParse(endTimeStr ?? '');
    if (end == null) return false;
    return DateTime.now().isAfter(end);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Assessments: "+widget.courseName)),
      body: Column(
        children: [
          if (widget.studentName != null || widget.studentRoll != null)
            // Beautiful profile card similar to evaluation page
            Center(
              child: Container(
                width: double.infinity,
                margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF004AAD), Color(0xFF2196F3), Color(0xFF90CAF9)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.blue.shade100.withOpacity(0.3),
                      blurRadius: 12,
                      offset: Offset(0, 6),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    // Online/Offline status
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          isOnline ? Icons.wifi : Icons.wifi_off,
                          color: isOnline ? Colors.lightGreen : Colors.orange,
                          size: 18,
                        ),
                        SizedBox(width: 8),
                        Text(
                          isOnline ? 'Online' : 'Offline',
                          style: TextStyle(
                            color: isOnline ? Colors.lightGreen : Colors.orange,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 12),
                    // Student info
                    if (widget.studentRoll != null && widget.studentRoll!.isNotEmpty)
                      Text(
                        widget.studentRoll!,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 22,
                          color: Colors.white,
                        ),
                      ),
                    SizedBox(height: 6),
                    if (widget.studentName != null && widget.studentName!.isNotEmpty)
                      Text(
                        widget.studentName!,
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.white.withOpacity(0.9),
                        ),
                      ),
                    SizedBox(height: 8),
                    Text(
                      'Course: ${widget.courseName}',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.white.withOpacity(0.8),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Expanded(
            child: assessments.isEmpty
                ? const Center(child: Text("No assessments found."))
                : ListView.builder(
                    itemCount: assessments.length,
                    itemBuilder: (context, index) {
                      final item = assessments[index];
                      final title = item['assessment'] ?? 'Unnamed';
                      final id = item['id'];
                      final startTime = formatDateTime(item['start_time']);
                      final endTime = formatDateTime(item['end_time']);
                      final isExpired = isAssessmentExpired(item['end_time']);

                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        child: ListTile(
                          title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text('Start: $startTime\nEnd: $endTime'),
                          trailing: isExpired
                              ? const Text("Assessment Ended", style: TextStyle(color: Color.fromARGB(255, 177, 5, 5)))
                              : ElevatedButton(
                                  onPressed: () {
                                    Get.to(() => AddEvaluationPage(
                                          assessmentId: id,
                                          assessmentName: title,
                                          studentName: widget.studentName,
                                          studentRoll: widget.studentRoll,
                                        ));
                                  },
                                  child: const Text("Add Evaluation"),
                                ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
