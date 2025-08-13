import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class ViewResultPage extends StatefulWidget {
  const ViewResultPage({super.key});

  @override
  State<ViewResultPage> createState() => _ViewResultPageState();
}

class _ViewResultPageState extends State<ViewResultPage> {
  String? studentRoll;
  List<Map<String, dynamic>> assessments = [];
  Map<String, dynamic>? selectedAssessment;

  List<Map<String, dynamic>> categories = [];
  List<Map<String, dynamic>> evaluations = [];
  double collectivePercentage = 0.0;
  bool isLoading = false;
  String? error;

  @override
  void initState() {
    super.initState();
    loadStudentAndFetchAssessments();
  }

  Future<void> loadStudentAndFetchAssessments() async {
    final prefs = await SharedPreferences.getInstance();
    final roll = prefs.getString('roll_number');

    if (roll == null) {
      Get.snackbar("Error", "Student roll number not found. Login again.",
          backgroundColor: Colors.red.shade100);
      return;
    }

    studentRoll = roll;
    final url = Uri.parse(
        'https://moosaalvi.pythonanywhere.com/api/student_assessments/?student_roll=$roll');

    try {
      final resp = await http.get(url);
      if (resp.statusCode == 200) {
        assessments =
            List<Map<String, dynamic>>.from(jsonDecode(resp.body));
        setState(() {});
      } else {
        error = "Failed to load assessments: ${resp.statusCode}";
      }
    } catch (e) {
      error = "Error loading assessments: $e";
    }
  }

  Future<void> fetchCategories(int assessmentId) async {
    final url = Uri.parse(
        'https://moosaalvi.pythonanywhere.com/api/assessments/categories/?assessment_id=$assessmentId');
    try {
      final resp = await http.get(url);
      if (resp.statusCode == 200) {
        categories = List<Map<String, dynamic>>.from(jsonDecode(resp.body));
      } else {
        throw Exception("Status ${resp.statusCode}");
      }
    } catch (e) {
      print("Category error: $e");
    }
  }

  Future<void> fetchEvaluations() async {
    if (studentRoll == null || selectedAssessment == null) return;

    final id = selectedAssessment!['id'];
    final encodedRoll = Uri.encodeQueryComponent(studentRoll!);
    final url = Uri.parse(
        'https://moosaalvi.pythonanywhere.com/api/assessments/evaluations/?assessment_id=$id&evaluation_of_student=$encodedRoll');

    setState(() {
      isLoading = true;
      error = null;
      evaluations = [];
      collectivePercentage = 0.0;
    });

    try {
      final resp = await http.get(url);
      if (resp.statusCode == 200) {
        evaluations = List<Map<String, dynamic>>.from(jsonDecode(resp.body));
        calculateCollectivePercentage();
      } else {
        error = "Failed to fetch evaluations: ${resp.statusCode}";
      }
    } catch (e) {
      error = "Error fetching evaluations: $e";
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  void calculateCollectivePercentage() {
    double obtained = 0.0;
    double max = 0.0;

    for (var cat in categories) {
      if (cat['type'] != 'text') {
        max += (cat['marks'] as num).toDouble();
      }
    }

    for (var eval in evaluations) {
      if (eval['obtained_marks'] != null) {
        obtained += (eval['obtained_marks'] as num).toDouble();
      }
    }

    collectivePercentage = max > 0 ? (obtained / max) * 100 : 0.0;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("View Results")),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: assessments.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Select an Assessment:",
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  DropdownButton<Map<String, dynamic>>(
                    isExpanded: true,
                    value: selectedAssessment,
                    hint: const Text("Choose Assessment"),
                    items: assessments
                        .map((a) => DropdownMenuItem(
                              value: a,
                              child: Text(a['title']),
                            ))
                        .toList(),
                    onChanged: (val) async {
                      selectedAssessment = val;
                      await fetchCategories(val!['id']);
                      await fetchEvaluations();
                    },
                  ),
                  const SizedBox(height: 20),
                  if (isLoading) const LinearProgressIndicator(),
                  if (error != null)
                    Text(error!, style: const TextStyle(color: Colors.red)),
                  if (evaluations.isNotEmpty) ...[
                    Text(
                      "Collective: ${collectivePercentage.toStringAsFixed(2)}%",
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const SizedBox(height: 10),
                    const Text("Evaluations:",
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          columns: [
                            const DataColumn(
                                label: Text("Category",
                                    style:
                                        TextStyle(fontWeight: FontWeight.bold))),
                            const DataColumn(
                                label: Text("Marks",
                                    style:
                                        TextStyle(fontWeight: FontWeight.bold))),
                          ],
                          rows: evaluations
                              .map((e) => DataRow(cells: [
                                    DataCell(Text(e['category_name'] ?? '-')),
                                    DataCell(Text(e['obtained_marks']?.toString() ?? e['comment_text'] ?? '-')),
                                  ]))
                              .toList(),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
      ),
    );
  }
}
