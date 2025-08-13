import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'add_category_page.dart';

class AssessmentPage extends StatefulWidget {
  final int subjectId;
  final String subjectName;

  const AssessmentPage({required this.subjectId, required this.subjectName});

  @override
  _AssessmentPageState createState() => _AssessmentPageState();
}

class _AssessmentPageState extends State<AssessmentPage> with SingleTickerProviderStateMixin {
  final TextEditingController _controller = TextEditingController();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  DateTime? _startDateTime;
  DateTime? _endDateTime;

  List<Map<String, dynamic>> assessments = [];
  bool _isSubmitting = false;
  late AnimationController _shakeController;
  late Animation<double> _offsetAnimation;
  
  File? _profileImage;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _loadCachedData();
    _fetchAssessments();
    _loadProfileImage();
    _shakeController = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    _offsetAnimation = Tween(begin: 0.0, end: 24.0).chain(CurveTween(curve: Curves.elasticIn)).animate(_shakeController);
  }

  @override
  void dispose() {
    _shakeController.dispose();
    super.dispose();
  }

  Future<void> _loadCachedData() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? cachedData = prefs.getString('assessments_${widget.subjectId}');
    if (cachedData != null) {
      final List decoded = jsonDecode(cachedData);
      setState(() {
        assessments = decoded.cast<Map<String, dynamic>>();
      });
    }
  }

  Future<void> _showEditDialog(Map<String, dynamic> item) async {
  final TextEditingController editController = TextEditingController(text: item['assessment'] ?? '');
  DateTime? editStartDateTime = DateTime.tryParse(item['start_time'] ?? '') ?? _startDateTime;
  DateTime? editEndDateTime = DateTime.tryParse(item['end_time'] ?? '') ?? _endDateTime;
  final GlobalKey<FormState> editFormKey = GlobalKey<FormState>();

  await showDialog(
    context: context,
    builder: (context) {
      return StatefulBuilder(builder: (context, setModalState) {
        return AlertDialog(
          title: const Text('Edit Assessment'),
          content: Form(
            key: editFormKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: editController,
                  decoration: const InputDecoration(labelText: 'Assessment'),
                  validator: (value) => (value == null || value.trim().isEmpty) ? 'This field is required' : null,
                ),
                const SizedBox(height: 10),
                OutlinedButton(
                  onPressed: () async {
                    final pickedDate = await showDatePicker(
                      context: context,
                      initialDate: editStartDateTime ?? DateTime.now(),
                      firstDate: DateTime.now().subtract(const Duration(days: 365)),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (pickedDate == null) return;
                    final pickedTime = await showTimePicker(
                      context: context,
                      initialTime: TimeOfDay.fromDateTime(editStartDateTime ?? DateTime.now()),
                    );
                    if (pickedTime == null) return;
                    setModalState(() {
                      editStartDateTime = DateTime(
                        pickedDate.year,
                        pickedDate.month,
                        pickedDate.day,
                        pickedTime.hour,
                        pickedTime.minute,
                      );
                    });
                  },
                  child: Text('Start: ${formatDateTime(editStartDateTime)}'),
                ),
                OutlinedButton(
                  onPressed: () async {
                    final pickedDate = await showDatePicker(
                      context: context,
                      initialDate: editEndDateTime ?? DateTime.now(),
                      firstDate: DateTime.now().subtract(const Duration(days: 365)),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (pickedDate == null) return;
                    final pickedTime = await showTimePicker(
                      context: context,
                      initialTime: TimeOfDay.fromDateTime(editEndDateTime ?? DateTime.now()),
                    );
                    if (pickedTime == null) return;
                    setModalState(() {
                      editEndDateTime = DateTime(
                        pickedDate.year,
                        pickedDate.month,
                        pickedDate.day,
                        pickedTime.hour,
                        pickedTime.minute,
                      );
                    });
                  },
                  child: Text('End: ${formatDateTime(editEndDateTime)}'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                if (!editFormKey.currentState!.validate() || editStartDateTime == null || editEndDateTime == null) {
                  Get.snackbar("Error", "All fields including dates are required", backgroundColor: Colors.red.shade100);
                  return;
                }
                if (editStartDateTime!.isAfter(editEndDateTime!)) {
                  Get.snackbar("Error", "End date/time must be after or equal to Start date/time", backgroundColor: Colors.red.shade100);
                  return;
                }
                final url = Uri.parse('https://moosaalvi.pythonanywhere.com/api/assessments/${item['id']}/');
                final response = await http.put(
                  url,
                  headers: {'Content-Type': 'application/json'},
                  body: jsonEncode({
                    'assessment': editController.text.trim(),
                    'course_id': widget.subjectId,
                    'start_time': editStartDateTime!.toIso8601String(),
                    'end_time': editEndDateTime!.toIso8601String(),
                  }),
                );
                if (response.statusCode == 200 || response.statusCode == 201) {
                  Get.snackbar("Success", "Assessment Updated!", backgroundColor: Colors.green.shade100);
                  await _fetchAssessments();
                  Navigator.of(context).pop();
                } else {
                  Get.snackbar("Error", "Failed to update assessment");
                }
              },
              child: const Text('Save'),
            ),
          ],
        );
      });
    },
  );
}


  Future<void> _cacheData(List<Map<String, dynamic>> data) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('assessments_${widget.subjectId}', jsonEncode(data));
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
        await _saveProfileImage(picked.path);
        
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

  void _showProfileImageDialog() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding: EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Profile Picture',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF004AAD),
                ),
              ),
              SizedBox(height: 20),
              Container(
                width: 200,
                height: 200,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Color(0xFF004AAD), width: 3),
                ),
                child: ClipOval(
                  child: _profileImage != null
                      ? Image.file(
                          _profileImage!,
                          fit: BoxFit.cover,
                        )
                      : Container(
                          color: Colors.grey[200],
                          child: Icon(
                            Icons.person,
                            size: 100,
                            color: Colors.grey[400],
                          ),
                        ),
                ),
              ),
              SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton.icon(
                    onPressed: _pickImage,
                    icon: Icon(Icons.edit),
                    label: Text('Change'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Color(0xFF004AAD),
                      foregroundColor: Colors.white,
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.close),
                    label: Text('Close'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.grey,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _fetchAssessments() async {
    final url = Uri.parse('https://moosaalvi.pythonanywhere.com/api/assessments/?course_id=${widget.subjectId}');
    
    try {
      final response = await http.get(url);
      
      if (response.statusCode == 200) {
        final List data = jsonDecode(response.body);
        
        if (mounted) {
          setState(() {
            assessments = data.cast<Map<String, dynamic>>().reversed.toList();
          });
        }
        await _cacheData(assessments);
      } else {
        Get.snackbar("Error", "Failed to fetch data: ${response.statusCode}");
      }
    } catch (e) {
      Get.snackbar("Offline", "Showing cached assessments");
    }
  }

  Future<void> _submitAssessment() async {
    if (!_formKey.currentState!.validate() || _startDateTime == null || _endDateTime == null) {
      _shakeController.forward(from: 0.0);
      Get.snackbar("Error", "All fields including dates are required", backgroundColor: Colors.red.shade100);
      return;
    }
    if (_endDateTime!.isBefore(_startDateTime!)) {
      Get.snackbar("Error", "End date/time must be after or equal to Start date/time", backgroundColor: Colors.red.shade100);
      return;
    }
    setState(() => _isSubmitting = true);

    final text = _controller.text.trim();
    final url = Uri.parse('https://moosaalvi.pythonanywhere.com/api/assessments/');
    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'assessment': text,
        'course_id': widget.subjectId,
        'start_time': _startDateTime!.toIso8601String(),
        'end_time': _endDateTime!.toIso8601String(),
      }),
    );

    setState(() => _isSubmitting = false);

    if (response.statusCode == 200 || response.statusCode == 201) {
      Get.snackbar("Success", "Assessment Saved!", backgroundColor: Colors.green.shade100);
      _controller.clear();
      _startDateTime = null;
      _endDateTime = null;
      await _fetchAssessments();
    } else {
      Get.snackbar("Error", "Failed to save assessment");
    }
  }

  Future<void> _deleteAssessment(int id) async {
    bool? confirm = await Get.dialog<bool>(
      AlertDialog(
        title: const Text("Confirm"),
        content: const Text("Are you sure you want to delete this assessment?"),
        actions: [
          TextButton(onPressed: () => Get.back(result: false), child: const Text("Cancel")),
          ElevatedButton(onPressed: () => Get.back(result: true), child: const Text("Delete")),
        ],
      ),
    );

    if (confirm != true) return;

    final url = Uri.parse('https://moosaalvi.pythonanywhere.com/api/assessments/$id/');
    final response = await http.delete(url);

    if (response.statusCode == 200 || response.statusCode == 204) {
      Get.snackbar("Deleted", "Assessment removed", backgroundColor: Colors.red.shade100);
      await _fetchAssessments();
    } else {
      Get.snackbar("Error", "Failed to delete assessment");
    }
  }

  Future<void> _pickDateTime({required bool isStart}) async {
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (pickedDate == null) return;

    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (pickedTime == null) return;

    final dateTime = DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
      pickedTime.hour,
      pickedTime.minute,
    );

    setState(() {
      if (isStart) {
        _startDateTime = dateTime;
      } else {
        _endDateTime = dateTime;
      }
    });
  }

  String formatDateTime(DateTime? dt) => dt == null ? 'Select' : DateFormat('dd MMM yyyy - hh:mm a').format(dt);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.subjectName} - Assessments'),
        actions: [
          GestureDetector(
            onTap: _showProfileImageDialog,
            child: Container(
              margin: EdgeInsets.only(right: 16),
              child: CircleAvatar(
                radius: 20,
                backgroundColor: Colors.white,
                child: _profileImage != null
                    ? ClipOval(
                        child: Image.file(
                          _profileImage!,
                          width: 40,
                          height: 40,
                          fit: BoxFit.cover,
                        ),
                      )
                    : Icon(
                        Icons.person,
                        color: Color(0xFF004AAD),
                        size: 24,
                      ),
              ),
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            const Text(
              'Create Assessment',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            Form(
              key: _formKey,
              child: Column(
                children: [
                  TextFormField(
                    controller: _controller,
                    decoration: const InputDecoration(labelText: 'Assessment Name'),
                    validator: (value) => (value == null || value.trim().isEmpty) ? 'Assessment name is required' : null,
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => _pickDateTime(isStart: true),
                          child: Text('Start: ${formatDateTime(_startDateTime)}'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => _pickDateTime(isStart: false),
                          child: Text('End: ${formatDateTime(_endDateTime)}'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            AnimatedBuilder(
              animation: _shakeController,
              builder: (context, child) {
                return Transform.translate(
                  offset: Offset(_offsetAnimation.value, 0),
                  child: ElevatedButton.icon(
                    icon: _isSubmitting
                        ? SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.save),
                    label: Text(_isSubmitting ? 'Please Wait...' : 'Submit'),
                    onPressed: _isSubmitting ? null : _submitAssessment,
                  ),
                );
              },
            ),
            const SizedBox(height: 30),
            const Text('Saved Assessments', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Expanded(
              child: assessments.isEmpty
                  ? const Text('No assessments yet.')
                  : ListView.builder(
                      itemCount: assessments.length,
                      itemBuilder: (context, index) {
                        final item = assessments[index];
                        final startTimeRaw = item['start_time'];
                        final endTimeRaw = item['end_time'];
                        final createdAtRaw = item['created_at'];
                        DateTime? startTime = startTimeRaw != null && startTimeRaw.toString().isNotEmpty ? DateTime.tryParse(startTimeRaw) : null;
                        DateTime? endTime = endTimeRaw != null && endTimeRaw.toString().isNotEmpty ? DateTime.tryParse(endTimeRaw) : null;
                        DateTime? createdAt = createdAtRaw != null && createdAtRaw.toString().isNotEmpty ? DateTime.tryParse(createdAtRaw) : null;

                        String startText = startTime != null ? formatDateTime(startTime) : 'N/A';
                        String endText = endTime != null ? formatDateTime(endTime) : 'N/A';
                        String createdText = createdAt != null ? formatDateTime(createdAt) : 'N/A';

                        return Card(
                          child: ListTile(
                            title: Text(item['assessment'] ?? ''),
                            subtitle: Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(text: 'Start: $startText\n'),
                                  TextSpan(text: 'End: $endText\n'),
                                  TextSpan(text: 'Added: $createdText'),
                                ],
                              ),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.delete, color: Colors.red),
                                  onPressed: () => _deleteAssessment(item['id']),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.add, color: Colors.blue),
                                  tooltip: "Add Category",
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => AddCategoryPage(assessmentId: item['id']),
                                      ),
                                    );
                                  },
                                ),
                                IconButton(
                                  icon: const Icon(Icons.edit, color: Colors.orange),
                                  tooltip: "Edit Assessment",
                                  onPressed: () {
                                    _showEditDialog(item);
                                  },
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
