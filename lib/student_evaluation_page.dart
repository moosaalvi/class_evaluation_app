import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:animate_do/animate_do.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'dart:async';

class AddEvaluationPage extends StatefulWidget {
  final int assessmentId;
  final String assessmentName;
  final String? studentName;
  final String? studentRoll;
  const AddEvaluationPage({
    required this.assessmentId,
    required this.assessmentName,
    this.studentName,
    this.studentRoll,
    super.key,
  });

  @override
  _AddEvaluationPageState createState() => _AddEvaluationPageState();
}

class _AddEvaluationPageState extends State<AddEvaluationPage>
    with SingleTickerProviderStateMixin {
  List categories = [];
  List<String> rollNumbers = [];
  List<String> filteredRollNumbers = [];
  Map<String, String> rollNumberToName = {}; // Map roll number to student name
  final Map<int, TextEditingController> markControllers = {};
  final Map<int, dynamic> dropdownValues = {};
  final TextEditingController searchController = TextEditingController();
  final TextEditingController filterController = TextEditingController();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final Map<int, GlobalKey> categoryKeys = {};
  final GlobalKey evaluatedOfKey = GlobalKey();

  String? selectedRollNumber;
  String? evaluatedOfError;
  String? submitError;
  bool isOnline = true;
  late StreamSubscription<ConnectivityResult> _connectivitySubscription;

  List<String> submittedRollNumbers = [];
  List<Map<String, dynamic>> submittedEvaluations = [];
  List<Map<String, dynamic>> filteredEvaluations = [];
  List<Map<String, dynamic>> pendingEvaluations = []; // New: offline submissions

  final ScrollController _scrollController = ScrollController();
  bool showNotFound = false;
  bool isSubmitting = false;
  int retryCount = 0;
  static const int maxRetries = 3;

  late AnimationController _shakeController;
  late Animation<double> _shakeAnimation;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _shakeAnimation =
        TweenSequence([
            TweenSequenceItem(
              tween: Tween<double>(begin: 0, end: 10),
              weight: 25,
            ),
            TweenSequenceItem(
              tween: Tween<double>(begin: 10, end: -10),
              weight: 50,
            ),
            TweenSequenceItem(
              tween: Tween<double>(begin: -10, end: 0),
              weight: 25,
            ),
          ]).animate(
            CurvedAnimation(parent: _shakeController, curve: Curves.easeInOut),
          )
          ..addListener(() => setState(() {}))
          ..addStatusListener((status) {
            if (status == AnimationStatus.completed) {
              _shakeController.reset();
            }
          });

    if (widget.assessmentId <= 0 || widget.assessmentId.runtimeType != int) {
      Get.snackbar(
        "Error",
        "Invalid assessment ID: \\${widget.assessmentId}",
        backgroundColor: Colors.red.shade100,
        duration: const Duration(seconds: 5),
      );
      print(
        "ERROR: Invalid assessmentId: \\${widget.assessmentId}, Type: \\${widget.assessmentId.runtimeType}",
      );
    }
    print(
      "Initialized with assessmentId: \\${widget.assessmentId}, Type: \\${widget.assessmentId.runtimeType}",
    );

    loadCachedData();
    searchController.addListener(_filterRollNumbers);
    filterController.addListener(_filterEvaluations);
    
    // Initialize network monitoring
    _initializeNetworkMonitoring();
    
    // Auto-load evaluations for logged-in student
    if (widget.studentRoll != null && widget.studentRoll!.isNotEmpty) {
      fetchSubmittedRollNumbers(widget.studentRoll!.toUpperCase());
      fetchSubmittedEvaluations(widget.studentRoll!.toUpperCase());
      loadPendingEvaluations(); // Load offline submissions
    }
  }

  @override
  void dispose() {
    _shakeController.dispose();
    _connectivitySubscription.cancel();
    searchController.removeListener(_filterRollNumbers);
    searchController.dispose();
    filterController.removeListener(_filterEvaluations);
    filterController.dispose();
    markControllers.values.forEach((c) => c.dispose());
    _scrollController.dispose();
    super.dispose();
  }

  // Initialize network monitoring for real-time status updates
  void _initializeNetworkMonitoring() async {
    // Check initial connectivity
    final connectivityResult = await Connectivity().checkConnectivity();
    _updateNetworkStatus(connectivityResult);
    
    // Listen for connectivity changes
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen(
      (ConnectivityResult result) {
        _updateNetworkStatus(result);
      },
    );
  }

  void _updateNetworkStatus(ConnectivityResult result) async {
    final wasOnline = isOnline;
    final newOnlineStatus = result != ConnectivityResult.none;
    
    if (wasOnline != newOnlineStatus) {
      setState(() {
        isOnline = newOnlineStatus;
      });
      
      if (newOnlineStatus && pendingEvaluations.isNotEmpty) {
        // Auto-upload pending evaluations when coming online
        await uploadPendingEvaluations();
      }
      
      // Show status change notification
      Get.snackbar(
        isOnline ? "Connected" : "Disconnected",
        isOnline ? "You're back online!" : "Working in offline mode",
        backgroundColor: isOnline ? Colors.lightBlue.shade100 : Colors.orange.shade100,
        icon: Icon(
          isOnline ? Icons.wifi : Icons.wifi_off,
          color: isOnline ? Colors.blue : Colors.orange,
        ),
        duration: Duration(seconds: 2),
      );
    }
  }

  void _filterRollNumbers() {
    final q = searchController.text.trim().toUpperCase();
    setState(() {
      if (q.isEmpty) {
        filteredRollNumbers = rollNumbers;
        showNotFound = false;
      } else {
        filteredRollNumbers = rollNumbers.where((r) => 
          r.contains(q) || (rollNumberToName[r] ?? '').toUpperCase().contains(q)
        ).toList();
        showNotFound = filteredRollNumbers.isEmpty;
      }
    });
  }

  void _filterEvaluations() {
    final q = filterController.text.trim().toUpperCase();
    setState(() {
      if (q.isEmpty) {
        filteredEvaluations = submittedEvaluations;
      } else {
        filteredEvaluations = submittedEvaluations
            .where(
              (eval) {
                final roll = eval['evaluation_of_student'].toUpperCase();
                final name = (rollNumberToName[eval['evaluation_of_student']] ?? '').toUpperCase();
                return roll.contains(q) || name.contains(q);
              },
            )
            .toList();
      }
    });
  }

  Future<void> loadCachedData() async {
    final prefs = await SharedPreferences.getInstance();
    final rolls = prefs.getString('cached_rolls');
    if (rolls != null) {
      rollNumbers = List<String>.from(jsonDecode(rolls));
      filteredRollNumbers = rollNumbers;
      // Load cached roll number to name mapping
      final cachedNames = prefs.getString('cached_roll_names');
      if (cachedNames != null) {
        rollNumberToName = Map<String, String>.from(jsonDecode(cachedNames));
      }
    }
    final cats = prefs.getString('categories_${widget.assessmentId}');
    if (cats != null) {
      categories = jsonDecode(cats);
      categories.sort(
        (a, b) => a['type'] == 'text' && b['type'] != 'text' ? 1 : -1,
      );
      for (var cat in categories) {
        markControllers[cat['id']] = TextEditingController();
        dropdownValues[cat['id']] = null;
        categoryKeys[cat['id']] = GlobalKey();
      }
    }
    
    // Load cached submitted evaluations
    final cachedEvals = prefs.getString('submitted_evaluations_${widget.assessmentId}_${widget.studentRoll}');
    if (cachedEvals != null) {
      submittedEvaluations = List<Map<String, dynamic>>.from(jsonDecode(cachedEvals));
      filteredEvaluations = submittedEvaluations;
    }
    
    // Load cached submitted roll numbers
    final cachedSubmitted = prefs.getString('submitted_rolls_${widget.assessmentId}_${widget.studentRoll}');
    if (cachedSubmitted != null) {
      submittedRollNumbers = List<String>.from(jsonDecode(cachedSubmitted));
    }
    
    setState(() {});
    await fetchAndCacheRollNumbers();
    await fetchAndCacheCategories();
  }

  // New: Load pending offline evaluations
  Future<void> loadPendingEvaluations() async {
    final prefs = await SharedPreferences.getInstance();
    final pending = prefs.getString('pending_evaluations_${widget.assessmentId}_${widget.studentRoll}');
    if (pending != null) {
      pendingEvaluations = List<Map<String, dynamic>>.from(jsonDecode(pending));
      setState(() {});
    }
  }

  // New: Save pending evaluation to local storage
  Future<void> savePendingEvaluation(Map<String, dynamic> evaluation) async {
    final prefs = await SharedPreferences.getInstance();
    pendingEvaluations.add(evaluation);
    await prefs.setString('pending_evaluations_${widget.assessmentId}_${widget.studentRoll}', jsonEncode(pendingEvaluations));
  }

  // New: Remove pending evaluation after successful upload
  Future<void> removePendingEvaluation(int index) async {
    final prefs = await SharedPreferences.getInstance();
    pendingEvaluations.removeAt(index);
    await prefs.setString('pending_evaluations_${widget.assessmentId}_${widget.studentRoll}', jsonEncode(pendingEvaluations));
    setState(() {});
  }

  Future<void> fetchAndCacheRollNumbers() async {
    try {
      final url = Uri.parse(
        "https://moosaalvi.pythonanywhere.com/api/assessments/students/rollnumbers/",
      );
      print("Fetching roll numbers from: $url");
      final resp = await http.get(url);
      print("Fetching roll numbers: Status ${resp.statusCode}, URL: $url");
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        rollNumbers = List<String>.from(
          data.map((e) => e['roll_number'].toString().toUpperCase()),
        );
        // Build roll number to name mapping
        rollNumberToName = {};
        for (var student in data) {
          String roll = student['roll_number'].toString().toUpperCase();
          String name = student['name'] ?? 'Unknown';
          rollNumberToName[roll] = name;
        }
        filteredRollNumbers = rollNumbers;
        // Save to SharedPreferences with names
        final prefs = await SharedPreferences.getInstance();
        prefs.setString('cached_rolls', jsonEncode(rollNumbers));
        prefs.setString('cached_roll_names', jsonEncode(rollNumberToName));
        setState(() {
          isOnline = true;
        });
        
        // Auto-upload pending evaluations when coming online
        if (pendingEvaluations.isNotEmpty) {
          await uploadPendingEvaluations();
        }
      } else {
        throw Exception('Failed to load roll numbers');
      }
    } catch (e) {
      print("INFO: Loading roll numbers from cache due to network issue");
      // Load from cache silently - no error messages
      final prefs = await SharedPreferences.getInstance();
      final cachedRolls = prefs.getString('cached_rolls');
      final cachedNames = prefs.getString('cached_roll_names');
      if (cachedRolls != null) {
        rollNumbers = List<String>.from(jsonDecode(cachedRolls));
        filteredRollNumbers = rollNumbers;
        if (cachedNames != null) {
          rollNumberToName = Map<String, String>.from(jsonDecode(cachedNames));
        }
        setState(() {
          isOnline = false;
        });
      }
    }
  }

  Future<void> fetchAndCacheCategories() async {
    if (widget.assessmentId <= 0) {
      print(
        "ERROR: Skipping category fetch due to invalid assessmentId: ${widget.assessmentId}",
      );
      return;
    }
    try {
      final url = Uri.parse(
        "https://moosaalvi.pythonanywhere.com/api/assessments/categories/?assessment_id=${widget.assessmentId}",
      );
      print("Fetching categories from: $url");
      final resp = await http.get(url);
      print("Fetching categories: Status ${resp.statusCode}, URL: $url");
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        categories = data;
        categories.sort(
          (a, b) => a['type'] == 'text' && b['type'] != 'text' ? 1 : -1,
        );
        for (var cat in categories) {
          markControllers[cat['id']] = TextEditingController();
          dropdownValues[cat['id']] = null;
          categoryKeys[cat['id']] = GlobalKey();
        }
        SharedPreferences.getInstance().then(
          (prefs) => prefs.setString(
            'categories_${widget.assessmentId}',
            jsonEncode(data),
          ),
        );
        setState(() {});
      } else {
        // Silently handle errors - no snackbar messages
        print(
          "ERROR: Failed to load categories: ${resp.statusCode}, Body: ${resp.body}",
        );
      }
    } catch (e) {
      // Silently handle errors - no snackbar messages
      print("ERROR: Exception loading categories: $e");
    }
  }

  Future<void> fetchSubmittedRollNumbers(String by) async {
    if (by.isEmpty ||
        !RegExp(r'^BSCSF22E(0[1-9]|[12][0-9]|30)$').hasMatch(by)) {
      print(
        "ERROR: Invalid roll number format in fetchSubmittedRollNumbers: $by",
      );
      return;
    }
    if (widget.assessmentId <= 0) {
      print(
        "ERROR: Invalid assessmentId in fetchSubmittedRollNumbers: ${widget.assessmentId}",
      );
      return;
    }
    try {
      final encodedBy = Uri.encodeQueryComponent(by);
      final url = Uri.parse(
        "https://moosaalvi.pythonanywhere.com/api/assessments/evaluated-rollnumbers/?evaluation_by=$encodedBy&assessment_id=${widget.assessmentId}",
      );
      print("Fetching submitted roll numbers from: $url");
      final resp = await http.get(url);
      print(
        "Fetching submitted roll numbers: Status ${resp.statusCode}, URL: $url",
      );
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        submittedRollNumbers = List<String>.from(
          data['roll_numbers'].map((e) => e.toUpperCase()),
        );
        
        // Save to local storage
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('submitted_rolls_${widget.assessmentId}_${widget.studentRoll}', jsonEncode(submittedRollNumbers));
        
        setState(() {});
      } else {
        // Silently handle errors - no snackbar messages
        print(
          "ERROR: Failed to load submitted rolls: ${resp.statusCode}, Body: ${resp.body}",
        );
      }
    } catch (e) {
      // Silently handle errors - no snackbar messages
      print("ERROR: Exception loading submitted rolls: $e");
    }
  }

  Future<void> fetchSubmittedEvaluations(String by) async {
    if (by.isEmpty ||
        !RegExp(r'^BSCSF22E(0[1-9]|[12][0-9]|30)$').hasMatch(by)) {
      print(
        "ERROR: Invalid roll number format in fetchSubmittedEvaluations: $by",
      );
      return;
    }
    if (widget.assessmentId <= 0) {
      print(
        "ERROR: Invalid assessmentId in fetchSubmittedEvaluations: ${widget.assessmentId}",
      );
      return;
    }

    setState(() {
      submittedEvaluations = [];
      filteredEvaluations = [];
    });

    final encodedBy = Uri.encodeQueryComponent(by);
    final url = Uri.parse(
      "https://moosaalvi.pythonanywhere.com/api/assessments/evaluations/?evaluation_by=$encodedBy&assessment_id=${widget.assessmentId}",
    );
    print(
      "Attempt ${retryCount + 1}/$maxRetries - Fetching evaluations from: $url",
    );
    print("Parameters: evaluation_by=$by, assessmentId=${widget.assessmentId}");

    try {
      while (retryCount < maxRetries) {
        final resp = await http.get(
          url,
          headers: {
            'Accept': 'application/json',
            'Content-Type': 'application/json',
          },
        );
        print("Response status: ${resp.statusCode}");
        print("Response body: ${resp.body}");

        if (resp.statusCode == 200) {
          submittedEvaluations = List<Map<String, dynamic>>.from(
            jsonDecode(resp.body),
          );
          submittedEvaluations.sort(
            (a, b) => (b['id'] ?? 0).compareTo(a['id'] ?? 0),
          );
          filteredEvaluations = submittedEvaluations;
          print("SUCCESS: Fetched ${submittedEvaluations.length} evaluations");
          
          // Save to local storage
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('submitted_evaluations_${widget.assessmentId}_${widget.studentRoll}', jsonEncode(submittedEvaluations));
          
          setState(() {
            isOnline = true;
          });
          return;
        } else if (resp.statusCode == 400) {
          print("ERROR: 400 Bad Request");
          setState(() {
            isOnline = false;
          });
          return;
        } else if (resp.statusCode == 404) {
          print("ERROR: 404 Not Found: Assessment not found");
          setState(() {
            isOnline = false;
          });
          return;
        } else if (resp.statusCode == 500) {
          retryCount++;
          final errorMsg =
              jsonDecode(resp.body)['error'] ?? 'Internal server error';
          print(
            "ERROR: 500 Internal Server Error: $errorMsg (Attempt $retryCount)",
          );
          if (retryCount >= maxRetries) {
            setState(() {
              isOnline = false;
            });
          } else {
            print("Retrying after 500 error... Attempt ${retryCount + 1}");
            await Future.delayed(const Duration(seconds: 2));
          }
        } else {
          print(
            "ERROR: Unexpected status code: ${resp.statusCode}, Body: ${resp.body}",
          );
          setState(() {
            isOnline = false;
          });
          return;
        }
      }
    } catch (e) {
      retryCount++;
      print("ERROR: Exception fetching evaluations: $e (Attempt $retryCount)");
      setState(() {
        isOnline = false;
      });
      if (retryCount >= maxRetries) {
        // Load from cache if available
        print("INFO: Loading evaluations from cache if available");
      } else {
        print("Retrying after error: $e... Attempt ${retryCount + 1}");
        await Future.delayed(const Duration(seconds: 2));
      }
    } finally {
      setState(() {});
    }
  }

  // New: Upload pending evaluations when online
  Future<void> uploadPendingEvaluations() async {
    if (!isOnline || pendingEvaluations.isEmpty) return;
    
    for (int i = pendingEvaluations.length - 1; i >= 0; i--) {
      try {
        final eval = pendingEvaluations[i];
        final payload = List<Map<String, dynamic>>.from(eval['details']);
        
        final resp = await http.post(
          Uri.parse("https://moosaalvi.pythonanywhere.com/api/assessments/submit-evaluation/"),
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          body: jsonEncode(payload),
        );
        
        if (resp.statusCode == 200 || resp.statusCode == 201) {
          await removePendingEvaluation(i);
          print("SUCCESS: Uploaded pending evaluation for ${eval['evaluation_of_student']}");
        } else {
          print("ERROR: Failed to upload pending evaluation: ${resp.statusCode}");
        }
      } catch (e) {
        print("ERROR: Exception uploading pending evaluation: $e");
      }
    }
    
    // Refresh submitted evaluations after upload
    if (widget.studentRoll != null && widget.studentRoll!.isNotEmpty) {
      await fetchSubmittedEvaluations(widget.studentRoll!.toUpperCase());
    }
    
    if (pendingEvaluations.isEmpty) {
      Get.snackbar(
        "Success",
        "All pending evaluations uploaded successfully!",
        backgroundColor: Colors.green.shade100,
        duration: const Duration(seconds: 3),
      );
    }
  }

  // New: Show pending evaluations dialog with modern design
  void _showPendingEvaluationsDialog() {
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            width: double.infinity,
            height: 600,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.white.withOpacity(0.95),
                  Colors.white.withOpacity(0.85),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(25),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 20,
                  offset: Offset(0, 10),
                ),
              ],
              border: Border.all(
                color: Colors.white.withOpacity(0.3),
                width: 1.5,
              ),
            ),
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Column(
                children: [
                  // Header with modern design
                  Container(
                    padding: EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.orange.shade400, Colors.orange.shade600],
                      ),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(Icons.pending_actions, color: Colors.white, size: 24),
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Pending Evaluations',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              Text(
                                '${pendingEvaluations.length} evaluations waiting',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.white.withOpacity(0.8),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (pendingEvaluations.isNotEmpty && isOnline)
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: TextButton.icon(
                              icon: Icon(Icons.cloud_upload, size: 16, color: Colors.orange.shade600),
                              label: Text(
                                'Upload All',
                                style: TextStyle(
                                  color: Colors.orange.shade600,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                              onPressed: () async {
                                await uploadPendingEvaluations();
                                setDialogState(() {});
                              },
                            ),
                          ),
                      ],
                    ),
                  ),
                  SizedBox(height: 20),
                  if (pendingEvaluations.isEmpty)
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(15),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                padding: EdgeInsets.all(20),
                                decoration: BoxDecoration(
                                  color: Colors.green.shade100,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(Icons.cloud_done, size: 48, color: Colors.green.shade600),
                              ),
                              SizedBox(height: 20),
                              Text(
                                'All caught up!',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey.shade700,
                                ),
                              ),
                              SizedBox(height: 8),
                              Text(
                                'No pending evaluations',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey.shade500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    )
                  else
                    Expanded(
                      child: ListView.builder(
                        itemCount: pendingEvaluations.length,
                        itemBuilder: (context, index) {
                          final eval = pendingEvaluations[index];
                          final studentRoll = eval['evaluation_of_student'];
                          final studentName = rollNumberToName[studentRoll] ?? 'Unknown';
                          final timestamp = DateTime.parse(eval['timestamp']);
                          
                          return Container(
                            margin: EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Colors.white.withOpacity(0.9),
                                  Colors.white.withOpacity(0.7),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(15),
                              border: Border.all(color: Colors.orange.shade200),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.orange.withOpacity(0.1),
                                  blurRadius: 8,
                                  offset: Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Padding(
                              padding: EdgeInsets.all(16),
                              child: Row(
                                children: [
                                  Container(
                                    padding: EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [Colors.orange.shade400, Colors.orange.shade600],
                                      ),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Icon(Icons.schedule, color: Colors.white, size: 20),
                                  ),
                                  SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '$studentRoll - $studentName',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                            color: Colors.black87,
                                          ),
                                        ),
                                        SizedBox(height: 4),
                                        Text(
                                          'Saved: ${timestamp.day}/${timestamp.month}/${timestamp.year} ${timestamp.hour}:${timestamp.minute.toString().padLeft(2, '0')}',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey.shade600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (isOnline)
                                        Container(
                                          margin: EdgeInsets.only(right: 8),
                                          decoration: BoxDecoration(
                                            gradient: LinearGradient(
                                              colors: [Colors.green.shade400, Colors.green.shade600],
                                            ),
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: IconButton(
                                            icon: Icon(Icons.cloud_upload, color: Colors.white, size: 18),
                                            onPressed: () async {
                                              try {
                                                final payload = List<Map<String, dynamic>>.from(eval['details']);
                                                final resp = await http.post(
                                                  Uri.parse("https://moosaalvi.pythonanywhere.com/api/assessments/submit-evaluation/"),
                                                  headers: {
                                                    'Content-Type': 'application/json',
                                                    'Accept': 'application/json',
                                                  },
                                                  body: jsonEncode(payload),
                                                );
                                                
                                                if (resp.statusCode == 200 || resp.statusCode == 201) {
                                                  await removePendingEvaluation(index);
                                                  setDialogState(() {});
                                                  Get.snackbar(
                                                    "Success",
                                                    "Evaluation uploaded for $studentRoll",
                                                    backgroundColor: Colors.green.shade100,
                                                  );
                                                } else {
                                                  Get.snackbar(
                                                    "Error",
                                                    "Failed to upload evaluation",
                                                    backgroundColor: Colors.red.shade100,
                                                  );
                                                }
                                              } catch (e) {
                                                Get.snackbar(
                                                  "Error",
                                                  "Network error: $e",
                                                  backgroundColor: Colors.red.shade100,
                                                );
                                              }
                                            },
                                          ),
                                        ),
                                      Container(
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            colors: [Colors.red.shade400, Colors.red.shade600],
                                          ),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: IconButton(
                                          icon: Icon(Icons.delete, color: Colors.white, size: 18),
                                          onPressed: () async {
                                            await removePendingEvaluation(index);
                                            // Also remove from submitted roll numbers
                                            submittedRollNumbers.remove(studentRoll.toUpperCase());
                                            final prefs = await SharedPreferences.getInstance();
                                            await prefs.setString('submitted_rolls_${widget.assessmentId}_${widget.studentRoll}', jsonEncode(submittedRollNumbers));
                                            setDialogState(() {});
                                            setState(() {});
                                          },
                                        ),
                                      ),
                                    ],
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
          ),
        ),
      ),
    );
  }

  bool isSubmittedRoll(String roll) {
    // Check both submitted and pending evaluations
    final upperRoll = roll.toUpperCase();
    final inSubmitted = submittedRollNumbers.contains(upperRoll);
    final inPending = pendingEvaluations.any((eval) => 
      eval['evaluation_of_student'].toUpperCase() == upperRoll);
    return inSubmitted || inPending;
  }

  void startEditing(Map<String, dynamic> eval) {
    final Map<int, TextEditingController> editMarkControllers = {};
    final Map<int, dynamic> editDropdownValues = {};
    final GlobalKey<FormState> _editFormKey = GlobalKey<FormState>();
    String? updateError;

    for (var cat in categories) {
      final id = cat['id'];
      editMarkControllers[id] = TextEditingController();
      editDropdownValues[id] = null;
      final det = (eval['details'] ?? []).firstWhere(
        (d) => d['category_id'] == id,
        orElse: () => {},
      );
      editMarkControllers[id]?.text =
          det['obtained_marks']?.toString() ?? det['comment_text'] ?? '';
      editDropdownValues[id] = det['obtained_marks'];
    }

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setDialogState) => Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            width: 400,
            height: 600,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.white.withOpacity(0.95),
                  Colors.white.withOpacity(0.85),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(25),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 20,
                  offset: Offset(0, 10),
                ),
              ],
              border: Border.all(
                color: Colors.white.withOpacity(0.3),
                width: 1.5,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _editFormKey,
                child: Column(
                  children: [
                    // Header with modern design
                    Container(
                      padding: EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Colors.lightBlue.shade400, Colors.blue.shade600],
                        ),
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(Icons.edit, color: Colors.white, size: 20),
                          ),
                          SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "Edit Evaluation",
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 18,
                                    color: Colors.white,
                                  ),
                                ),
                                Text(
                                  "Student: ${eval['evaluation_of_student']}",
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.white.withOpacity(0.8),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: 20),
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          children: categories.map((cat) {
                            final id = cat['id'],
                                name = cat['category_name'],
                                marks = cat['marks'],
                                type = cat['type'];
                            return Container(
                              margin: EdgeInsets.only(bottom: 16),
                              padding: EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Colors.grey.shade50,
                                    Colors.white,
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(15),
                                border: Border.all(color: Colors.blue.shade200),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.blue.withOpacity(0.1),
                                    blurRadius: 6,
                                    offset: Offset(0, 3),
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        padding: EdgeInsets.all(6),
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            colors: type == 'text' 
                                              ? [Colors.indigo.shade400, Colors.indigo.shade600]
                                              : [Colors.lightBlue.shade400, Colors.blue.shade600],
                                          ),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Icon(
                                          type == 'text' ? Icons.comment : Icons.stars,
                                          color: Colors.white,
                                          size: 16,
                                        ),
                                      ),
                                      SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          type == 'text' ? name : "$name (Max $marks)",
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                            color: Colors.black87,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  SizedBox(height: 12),
                                  if (type == 'text')
                                    Container(
                                      decoration: BoxDecoration(
                                        color: Colors.grey.shade100,
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(color: Colors.grey.shade300),
                                      ),
                                      child: TextFormField(
                                        controller: editMarkControllers[id],
                                        maxLines: 3,
                                        decoration: InputDecoration(
                                          hintText: 'Enter comment',
                                          border: InputBorder.none,
                                          contentPadding: EdgeInsets.all(12),
                                          hintStyle: TextStyle(color: Colors.grey.shade500),
                                        ),
                                        style: TextStyle(fontSize: 13),
                                        autovalidateMode: AutovalidateMode.onUserInteraction,
                                        validator: (v) {
                                          final s = v?.trim() ?? '';
                                          if (s.isEmpty) return 'Required';
                                          if (s.length < 5) return 'Min 5 chars';
                                          return null;
                                        },
                                      ),
                                    )
                                  else
                                    Row(
                                      children: [
                                        Expanded(
                                          flex: 2,
                                          child: Container(
                                            decoration: BoxDecoration(
                                              color: Colors.grey.shade100,
                                              borderRadius: BorderRadius.circular(10),
                                              border: Border.all(color: Colors.grey.shade300),
                                            ),
                                            child: TextFormField(
                                              controller: editMarkControllers[id],
                                              keyboardType: TextInputType.numberWithOptions(decimal: true),
                                              inputFormatters: [
                                                FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                                              ],
                                              decoration: InputDecoration(
                                                labelText: 'Marks',
                                                border: InputBorder.none,
                                                contentPadding: EdgeInsets.all(12),
                                                labelStyle: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                                              ),
                                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                                              autovalidateMode: AutovalidateMode.onUserInteraction,
                                              validator: (v) {
                                                if (v == null || v.trim().isEmpty) return 'Required';
                                                final n = double.tryParse(v);
                                                if (n == null) return 'Only numbers';
                                                if (n < 0) return 'Invalid';
                                                if (n > marks) return 'Max $marks';
                                                return null;
                                              },
                                            ),
                                          ),
                                        ),
                                        SizedBox(width: 12),
                                        Expanded(
                                          child: Container(
                                            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                            decoration: BoxDecoration(
                                              gradient: LinearGradient(
                                                colors: [Colors.blue.shade50, Colors.blue.shade100],
                                              ),
                                              borderRadius: BorderRadius.circular(10),
                                              border: Border.all(color: Colors.blue.shade200),
                                            ),
                                            child: DropdownButtonHideUnderline(
                                              child: DropdownButton<int>(
                                                hint: Text(
                                                  "Quick",
                                                  style: TextStyle(
                                                    color: Colors.blue.shade600,
                                                    fontSize: 11,
                                                  ),
                                                ),
                                                value: (editDropdownValues[id] != null && editDropdownValues[id] >= 0 && editDropdownValues[id] <= marks) ? editDropdownValues[id] : null,
                                                isExpanded: true,
                                                icon: Icon(Icons.keyboard_arrow_down, color: Colors.blue.shade600, size: 16),
                                                items: List.generate(
                                                  marks + 1,
                                                  (i) => DropdownMenuItem(
                                                    value: i,
                                                    child: Text(
                                                      '$i',
                                                      style: TextStyle(
                                                        fontWeight: FontWeight.w600,
                                                        color: Colors.blue.shade700,
                                                        fontSize: 12,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                                onChanged: (v) {
                                                  setDialogState(() {
                                                    editMarkControllers[id]?.text = v?.toString() ?? '';
                                                    editDropdownValues[id] = v;
                                                  });
                                                },
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                    SizedBox(height: 20),
                    // Update button with modern design
                    Container(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: isSubmitting ? null : () async {
                          // Update logic here (keeping the existing logic)
                          if (!_editFormKey.currentState!.validate()) {
                            setDialogState(() {
                              updateError = 'Please fix errors above';
                            });
                            _shakeController.forward();
                            return;
                          }
                          setDialogState(() {
                            isSubmitting = true;
                            updateError = null;
                          });
                          final by = widget.studentRoll != null ? widget.studentRoll!.trim().toUpperCase() : '';
                          final of = eval['evaluation_of_student'].toUpperCase();
                          final payload = categories.map((cat) => {
                                "evaluation_by": by,
                                "evaluation_of_student": of,
                                "category_id": cat['id'],
                                "category_name": cat['category_name'],
                                "obtained_marks": cat['type'] == 'text'
                                ? null
                                : double.tryParse(editMarkControllers[cat['id']]?.text.trim() ?? '0') ?? 0.0,
                                "comment_text": cat['type'] == 'text'
                                ? editMarkControllers[cat['id']]?.text.trim()
                                : "",
                                "assessment": widget.assessmentId,
                                "status": "E",
                              }).toList();

                          final uri = "https://moosaalvi.pythonanywhere.com/api/assessments/evaluations/${eval['id']}/?assessment_id=${widget.assessmentId}";
                          print("Updating evaluation to: $uri");
                          print("Payload: ${jsonEncode(payload)}");

                          try {
                            final resp = await http.put(
                              Uri.parse(uri),
                              headers: {
                                'Content-Type': 'application/json',
                                'Accept': 'application/json',
                              },
                              body: jsonEncode(payload),
                            );
                            print("Update evaluation response: Status ${resp.statusCode}, Body: ${resp.body}");

                            if (resp.statusCode == 200 || resp.statusCode == 201) {
                              Get.snackbar(
                                "Success",
                                "Evaluation Updated",
                                backgroundColor: Colors.green.shade100,
                                duration: const Duration(seconds: 5),
                              );
                              await fetchSubmittedEvaluations(by);
                              Navigator.pop(context);
                            } else {
                              final errorMsg = jsonDecode(resp.body)['error'] ?? 'Update failed';
                              setDialogState(() {
                                updateError = errorMsg;
                              });
                              _shakeController.forward();
                              Get.snackbar(
                                "Error",
                                errorMsg,
                                backgroundColor: Colors.red.shade100,
                                duration: const Duration(seconds: 5),
                              );
                              print("ERROR: Update failed: ${resp.statusCode}, Error: $errorMsg");
                            }
                          } catch (e) {
                            setDialogState(() {
                              updateError = 'Network error: $e';
                            });
                            _shakeController.forward();
                            Get.snackbar(
                              "Error",
                              "Network error: $e",
                              backgroundColor: Colors.red.shade100,
                              duration: const Duration(seconds: 5),
                            );
                            print("ERROR: Exception updating evaluation: $e");
                          } finally {
                            setDialogState(() {
                              isSubmitting = false;
                            });
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          elevation: 0,
                          backgroundColor: Colors.transparent,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(25),
                          ),
                          padding: EdgeInsets.zero,
                        ),
                        child: Ink(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: isSubmitting
                                ? [Colors.grey.shade400, Colors.grey.shade500]
                                : [Colors.lightBlue.shade400, Colors.blue.shade600],
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                            ),
                            borderRadius: BorderRadius.circular(25),
                            boxShadow: [
                              BoxShadow(
                                color: (isSubmitting ? Colors.grey : Colors.blue).withOpacity(0.4),
                                blurRadius: 10,
                                offset: Offset(0, 6),
                              ),
                            ],
                          ),
                          child: Container(
                            alignment: Alignment.center,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                if (isSubmitting)
                                  SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                else
                                  Icon(Icons.update, color: Colors.white, size: 20),
                                SizedBox(width: 8),
                                Text(
                                  isSubmitting ? 'Updating...' : 'Update Evaluation',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (updateError != null)
                      Container(
                        margin: EdgeInsets.only(top: 12),
                        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.red.shade200),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.error_outline, color: Colors.red.shade600, size: 16),
                            SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                updateError!,
                                style: TextStyle(
                                  color: Colors.red.shade700,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void submitEvaluation() async {
    if (isSubmitting) {
      print("INFO: Submission already in progress, ignoring");
      return;
    }

    setState(() {
      isSubmitting = true;
      evaluatedOfError = submitError = null;
    });

    if (!_formKey.currentState!.validate()) {
      print("INFO: Form validation failed");
      _shakeController.forward();
      setState(() {
        isSubmitting = false;
        submitError = 'Please fix errors above';
      });
      return;
    }

    final by = widget.studentRoll != null ? widget.studentRoll!.trim().toUpperCase() : '';
    final of = selectedRollNumber!.toUpperCase();

    // Check for offline duplicates in pending evaluations
    final existsInPending = pendingEvaluations.any((eval) => 
      eval['evaluation_of_student'].toUpperCase() == of);
    
    if (existsInPending) {
      setState(() {
        isSubmitting = false;
        submitError = 'Evaluation for this student is already pending upload';
        evaluatedOfError = 'Already pending upload';
      });
      _shakeController.forward();
      return;
    }

    if (widget.assessmentId <= 0) {
      print("ERROR: Invalid assessmentId: \\${widget.assessmentId}");
      setState(() {
        isSubmitting = false;
        submitError = 'Invalid assessment ID';
      });
      return;
    }

    final payload = categories.map((cat) {
      final id = cat['id'];
      final type = cat['type'];
      final marksText = markControllers[id]?.text.trim() ?? '';
      return {
        "evaluation_by": by,
        "evaluation_of_student": of,
        "category_id": id,
        "category_name": cat['category_name'] ?? 'Unknown',
        "obtained_marks": type == 'text'
            ? null
            : double.tryParse(marksText.isEmpty ? '0' : marksText) ?? 0.0,
        "comment_text": type == 'text'
            ? (marksText.isEmpty ? '' : marksText)
            : '',
        "assessment": widget.assessmentId,
        "status": "E",
      };
    }).toList();

    if (!isOnline) {
      // Save to pending evaluations for offline submission
      final pendingEval = {
        'id': DateTime.now().millisecondsSinceEpoch, // Temporary ID
        'evaluation_of_student': of,
        'evaluation_by': by,
        'assessment_id': widget.assessmentId,
        'details': payload,
        'timestamp': DateTime.now().toIso8601String(),
        'status': 'pending'
      };
      
      await savePendingEvaluation(pendingEval);
      submittedRollNumbers.add(of); // Add to local submitted list
      
      // Save updated submitted rolls to local storage
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('submitted_rolls_${widget.assessmentId}_${widget.studentRoll}', jsonEncode(submittedRollNumbers));
      
      setState(() {
        isSubmitting = false;
      });
      
      Get.snackbar(
        "Saved Offline",
        "Evaluation saved locally. Will upload when online.",
        backgroundColor: Colors.orange.shade100,
        duration: const Duration(seconds: 5),
        icon: Icon(Icons.cloud_off, color: Colors.orange),
      );
      
      clearForm();
      return;
    }

    final uri =
        "https://moosaalvi.pythonanywhere.com/api/assessments/submit-evaluation/";
    print("Submitting evaluation to: $uri");
    print("Payload: ${jsonEncode(payload)}");

    try {
      final resp = await http.post(
        Uri.parse(uri),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode(payload),
      ).timeout(
        Duration(seconds: 30),
        onTimeout: () {
          throw Exception('Connection timeout');
        },
      );
      
      print(
        "Submit evaluation response: Status ${resp.statusCode}, Body: ${resp.body}",
      );

      if (resp.statusCode == 200 || resp.statusCode == 201) {
        print("SUCCESS: Evaluation submitted successfully");
        Get.snackbar(
          "Success",
          "Evaluation Submitted",
          backgroundColor: Colors.green.shade100,
          duration: const Duration(seconds: 5),
        );
        submittedRollNumbers.add(of);
        await fetchSubmittedEvaluations(by);
        clearForm();
      } else {
        String errorMsg = 'Submission failed: Status ${resp.statusCode}';
        try {
          final errorBody = jsonDecode(resp.body);
          errorMsg = errorBody['error'] ?? errorBody['detail'] ?? errorMsg;
        } catch (e) {
          print("ERROR: Failed to parse error response: $e");
        }
        print(
          "ERROR: Submission failed: Status ${resp.statusCode}, Error: $errorMsg",
        );
        
        // Save to pending if server error
        if (resp.statusCode >= 500) {
          final pendingEval = {
            'id': DateTime.now().millisecondsSinceEpoch,
            'evaluation_of_student': of,
            'evaluation_by': by,
            'assessment_id': widget.assessmentId,
            'details': payload,
            'timestamp': DateTime.now().toIso8601String(),
            'status': 'pending'
          };
          
          await savePendingEvaluation(pendingEval);
          Get.snackbar(
            "Saved Offline",
            "Server error. Evaluation saved locally for later upload.",
            backgroundColor: Colors.orange.shade100,
            duration: const Duration(seconds: 5),
          );
          clearForm();
        } else {
          Get.snackbar(
            "Error",
            errorMsg,
            backgroundColor: Colors.red.shade100,
            duration: const Duration(seconds: 5),
          );
          _shakeController.forward();
          setState(() {
            evaluatedOfError = errorMsg;
            submitError = errorMsg;
          });
        }
      }
    } catch (e) {
      print("ERROR: Exception submitting evaluation: $e");
      
      // Save to pending evaluations on network error
      final pendingEval = {
        'id': DateTime.now().millisecondsSinceEpoch,
        'evaluation_of_student': of,
        'evaluation_by': by,
        'assessment_id': widget.assessmentId,
        'details': payload,
        'timestamp': DateTime.now().toIso8601String(),
        'status': 'pending'
      };
      
      await savePendingEvaluation(pendingEval);
      submittedRollNumbers.add(of);
      
      // Save updated submitted rolls to local storage
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('submitted_rolls_${widget.assessmentId}_${widget.studentRoll}', jsonEncode(submittedRollNumbers));
      
      Get.snackbar(
        "Saved Offline",
        "Network error. Evaluation saved locally for later upload.",
        backgroundColor: Colors.orange.shade100,
        duration: const Duration(seconds: 5),
        icon: Icon(Icons.cloud_off, color: Colors.orange),
      );
      
      clearForm();
    } finally {
      setState(() {
        isSubmitting = false;
      });
      print("INFO: Submission process completed");
    }
  }

  void clearForm() {
    print("INFO: Starting form clear process");
    
    // Clear search controller first
    searchController.clear();
    
    // First pass: Clear all controllers and dropdown values immediately
    for (var cat in categories) {
      final id = cat['id'];
      if (markControllers.containsKey(id)) {
        markControllers[id]?.clear();
        print("DEBUG: Cleared controller for category $id");
      }
      dropdownValues[id] = null;
      print("DEBUG: Reset dropdown value for category $id");
    }
    
    // Clear the entire dropdown values map
    dropdownValues.clear();
    
    // Force immediate UI update with setState
    setState(() {
      selectedRollNumber = null;
      evaluatedOfError = null;
      submitError = null;
      filteredRollNumbers = rollNumbers;
      showNotFound = false;
      
      // Rebuild dropdown values map completely
      for (var cat in categories) {
        dropdownValues[cat['id']] = null;
      }
    });
    
    // Second pass: Double-check all controllers are cleared after setState
    Future.microtask(() {
      for (var cat in categories) {
        final id = cat['id'];
        if (markControllers.containsKey(id) && markControllers[id] != null) {
          if (markControllers[id]!.text.isNotEmpty) {
            print("WARNING: Controller $id still has text: '${markControllers[id]!.text}', clearing again");
            markControllers[id]!.clear();
          }
        }
      }
      
      // Reset form validation state
      if (_formKey.currentState != null) {
        _formKey.currentState!.reset();
      }
      
      // Final setState to ensure UI is completely refreshed
      setState(() {});
      
      print("INFO: Form clear process completed - all fields should be empty");
    });
  }

  void _showRollNumberDialog(BuildContext context) {
    final by = widget.studentRoll != null ? widget.studentRoll!.trim().toUpperCase() : '';
    if (by.isNotEmpty && rollNumbers.contains(by)) {
      fetchSubmittedRollNumbers(by);
    }
    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setDialogState) => Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            width: 350,
            height: 500,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.white.withOpacity(0.95),
                  Colors.white.withOpacity(0.85),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(25),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 20,
                  offset: Offset(0, 10),
                ),
              ],
              border: Border.all(
                color: Colors.white.withOpacity(0.3),
                width: 1.5,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  // Header with modern design
                  Container(
                    padding: EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.lightBlue.shade400, Colors.blue.shade600],
                      ),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(Icons.search, color: Colors.white, size: 20),
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Select Student',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: 20),
                  // Search field with modern design
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(color: Colors.blue.shade200),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.blue.withOpacity(0.1),
                          blurRadius: 8,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    child: TextField(
                      controller: searchController,
                      decoration: InputDecoration(
                        hintText: "Search by roll number or name",
                        border: InputBorder.none,
                        prefixIcon: Icon(Icons.search, color: Colors.blue.shade600),
                        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                        hintStyle: TextStyle(color: Colors.grey.shade500),
                      ),
                      onChanged: (_) => setDialogState(_filterRollNumbers),
                    ),
                  ),
                  SizedBox(height: 16),
                  if (showNotFound)
                    Container(
                      padding: EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.search_off, color: Colors.red.shade600, size: 20),
                          SizedBox(width: 8),
                          Text(
                            "No students found",
                            style: TextStyle(
                              color: Colors.red.shade700,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  SizedBox(height: 8),
                  Expanded(
                    child: ListView(
                      children: filteredRollNumbers.map((roll) {
                        final submitted = isSubmittedRoll(roll);
                        final isSelf = roll == (widget.studentRoll != null ? widget.studentRoll!.trim().toUpperCase() : null);
                        final studentName = rollNumberToName[roll] ?? 'Unknown';
                        return Container(
                          margin: EdgeInsets.only(bottom: 8),
                          child: InkWell(
                            onTap: submitted || isSelf ? null : () {
                              setState(() {
                                selectedRollNumber = roll;
                                evaluatedOfError = null;
                              });
                              Navigator.pop(context);
                            },
                            borderRadius: BorderRadius.circular(15),
                            child: Container(
                              padding: EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: submitted
                                      ? [Colors.green.shade50, Colors.green.shade100]
                                      : isSelf
                                      ? [Colors.red.shade50, Colors.red.shade100]
                                      : [Colors.blue.shade50, Colors.blue.shade100],
                                ),
                                borderRadius: BorderRadius.circular(15),
                                border: Border.all(
                                  color: submitted
                                      ? Colors.green.shade300
                                      : isSelf
                                      ? Colors.red.shade300
                                      : Colors.blue.shade300,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: (submitted ? Colors.green : isSelf ? Colors.red : Colors.blue).withOpacity(0.1),
                                    blurRadius: 6,
                                    offset: Offset(0, 3),
                                  ),
                                ],
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    padding: EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: submitted
                                            ? [Colors.green.shade400, Colors.green.shade600]
                                            : isSelf
                                            ? [Colors.red.shade400, Colors.red.shade600]
                                            : [Colors.blue.shade400, Colors.blue.shade600],
                                      ),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Icon(
                                      submitted
                                          ? Icons.check_circle
                                          : isSelf
                                          ? Icons.block
                                          : Icons.person,
                                      color: Colors.white,
                                      size: 20,
                                    ),
                                  ),
                                  SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          roll,
                                          style: TextStyle(
                                            color: submitted
                                                ? Colors.green.shade800
                                                : isSelf
                                                ? Colors.red.shade800
                                                : Colors.blue.shade800,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                          ),
                                        ),
                                        SizedBox(height: 4),
                                        Text(
                                          studentName,
                                          style: TextStyle(
                                            color: submitted
                                                ? Colors.green.shade600
                                                : isSelf
                                                ? Colors.red.shade600
                                                : Colors.blue.shade600,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (submitted || isSelf)
                                    Container(
                                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: submitted ? Colors.green.shade200 : Colors.red.shade200,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        submitted ? 'Done' : 'Self',
                                        style: TextStyle(
                                          color: submitted ? Colors.green.shade800 : Colors.red.shade800,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(70),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Color(0xFF2196F3),
                Color(0xFF1976D2),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 10,
                offset: Offset(0, 5),
              ),
            ],
          ),
          child: AppBar(
            title: Text(
              "Evaluate ${widget.assessmentName}",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: Colors.white,
              ),
            ),
            backgroundColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
              icon: Icon(Icons.arrow_back_ios, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
            actions: [
              // Manual upload button with better design
              if (pendingEvaluations.isNotEmpty)
                Container(
                  margin: EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: IconButton(
                    icon: Icon(Icons.cloud_upload, color: Colors.white),
                    tooltip: 'Upload Pending Evaluations',
                    onPressed: () async {
                      if (isOnline) {
                        await uploadPendingEvaluations();
                      } else {
                        Get.snackbar(
                          "Offline",
                          "Connect to internet to upload evaluations",
                          backgroundColor: Colors.orange.shade100,
                          icon: Icon(Icons.wifi_off, color: Colors.orange),
                        );
                      }
                    },
                  ),
                ),
              // Pending evaluations button with better positioning
              Container(
                margin: EdgeInsets.only(right: 16),
                child: Stack(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: IconButton(
                        icon: Icon(Icons.pending_actions, color: Colors.white),
                        tooltip: 'Pending Evaluations',
                        onPressed: _showPendingEvaluationsDialog,
                      ),
                    ),
                    if (pendingEvaluations.isNotEmpty)
                      Positioned(
                        right: 2,
                        top: 2,
                        child: Container(
                          padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Colors.orange.shade400, Colors.orange.shade600],
                            ),
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.orange.withOpacity(0.5),
                                blurRadius: 6,
                                offset: Offset(0, 3),
                              ),
                            ],
                          ),
                          constraints: BoxConstraints(minWidth: 20, minHeight: 20),
                          child: Text(
                            '${pendingEvaluations.length}',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Color(0xFF2196F3),
              Color(0xFF1976D2),
              Color(0xFF0D47A1),
              Color(0xFF0277BD),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            stops: [0.0, 0.3, 0.7, 1.0],
          ),
        ),
        child: categories.isEmpty
            ? Center(
                child: FadeInUp(
                  duration: Duration(milliseconds: 800),
                  child: Container(
                    padding: EdgeInsets.all(32),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.white.withOpacity(0.9),
                          Colors.white.withOpacity(0.7),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(25),
                      border: Border.all(color: Colors.white.withOpacity(0.3)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 20,
                          offset: Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Stack(
                          alignment: Alignment.center,
                          children: [
                            SpinKitRipple(
                              color: Colors.blue.shade200.withOpacity(0.6),
                              size: 120.0,
                            ),
                            SpinKitPulse(
                              color: Colors.lightBlue.shade400,
                              size: 80.0,
                            ),
                            Container(
                              padding: EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [Colors.lightBlue.shade400, Colors.blue.shade600],
                                ),
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.blue.withOpacity(0.3),
                                    blurRadius: 15,
                                    offset: Offset(0, 5),
                                  ),
                                ],
                              ),
                              child: Icon(
                                Icons.assessment,
                                color: Colors.white,
                                size: 32,
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 24),
                        FadeInUp(
                          duration: Duration(milliseconds: 1200),
                          delay: Duration(milliseconds: 400),
                          child: Text(
                            'Loading Assessment',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue.shade800,
                            ),
                          ),
                        ),
                        SizedBox(height: 8),
                        FadeInUp(
                          duration: Duration(milliseconds: 1200),
                          delay: Duration(milliseconds: 600),
                          child: Text(
                            'Preparing evaluation categories...',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.blue.shade600,
                            ),
                          ),
                        ),
                        SizedBox(height: 16),
                        SpinKitThreeBounce(
                          color: Colors.lightBlue.shade400,
                          size: 24.0,
                        ),
                      ],
                    ),
                  ),
                ),
              )
            : Container(
                margin: EdgeInsets.all(8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(25),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.3),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 20,
                      offset: Offset(0, 10),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(25),
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.white.withOpacity(0.25),
                          Colors.white.withOpacity(0.1),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Form(
                        key: _formKey,
                        child: SingleChildScrollView(
                          controller: _scrollController,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Modern Header Card
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(20),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      Colors.white.withOpacity(0.9),
                                      Colors.white.withOpacity(0.7),
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  borderRadius: BorderRadius.circular(20),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.1),
                                      blurRadius: 15,
                                      offset: Offset(0, 5),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  children: [
                                    // Online/Offline Status with trendy design
                                    Container(
                                      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          colors: isOnline 
                                            ? [Colors.lightBlue.shade400, Colors.blue.shade600]
                                            : [Colors.orange.shade400, Colors.orange.shade600],
                                        ),
                                        borderRadius: BorderRadius.circular(20),
                                        boxShadow: [
                                          BoxShadow(
                                            color: (isOnline ? Colors.blue : Colors.orange).withOpacity(0.3),
                                            blurRadius: 8,
                                            offset: Offset(0, 3),
                                          ),
                                        ],
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Container(
                                            width: 8,
                                            height: 8,
                                            decoration: BoxDecoration(
                                              color: Colors.white,
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                          SizedBox(width: 8),
                                          Text(
                                            isOnline ? 'Online' : 'Offline Mode',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    SizedBox(height: 16),
                                    // Student Info with modern design
                                    Row(
                                      children: [
                                        Container(
                                          padding: EdgeInsets.all(12),
                                          decoration: BoxDecoration(
                                            gradient: LinearGradient(
                                              colors: [Colors.blue.shade400, Colors.blue.shade600],
                                            ),
                                            borderRadius: BorderRadius.circular(15),
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.blue.withOpacity(0.3),
                                                blurRadius: 8,
                                                offset: Offset(0, 3),
                                              ),
                                            ],
                                          ),
                                          child: Icon(
                                            Icons.person,
                                            color: Colors.white,
                                            size: 24,
                                          ),
                                        ),
                                        SizedBox(width: 16),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                widget.studentRoll ?? '-',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 20,
                                                  color: Colors.black87,
                                                ),
                                              ),
                                              Text(
                                                widget.studentName ?? '-',
                                                style: TextStyle(
                                                  fontSize: 14,
                                                  color: Colors.grey.shade600,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                    SizedBox(height: 12),
                                    // Assessment Info
                                    Container(
                                      width: double.infinity,
                                      padding: EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: Colors.grey.shade50,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(color: Colors.grey.shade200),
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(Icons.assignment, color: Colors.blue.shade600, size: 20),
                                          SizedBox(width: 8),
                                          Text(
                                            'Assessment: ${widget.assessmentName}',
                                            style: TextStyle(
                                              fontSize: 14,
                                              color: Colors.blue.shade700,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              SizedBox(height: 20),
                              // Progress Card with modern design
                              FadeInUp(
                                duration: Duration(milliseconds: 500),
                                child: Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        Colors.white.withOpacity(0.9),
                                        Colors.white.withOpacity(0.6),
                                      ],
                                    ),
                                    borderRadius: BorderRadius.circular(18),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.1),
                                        blurRadius: 10,
                                        offset: Offset(0, 5),
                                      ),
                                    ],
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        padding: EdgeInsets.all(10),
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            colors: [Colors.lightBlue.shade400, Colors.blue.shade600],
                                          ),
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: Icon(Icons.analytics, color: Colors.white, size: 20),
                                      ),
                                      SizedBox(width: 16),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              "Evaluation Progress",
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 16,
                                                color: Colors.black87,
                                              ),
                                            ),
                                            SizedBox(height: 4),
                                            LinearProgressIndicator(
                                              value: rollNumbers.isEmpty ? 0 : submittedRollNumbers.length / rollNumbers.length,
                                              backgroundColor: Colors.grey.shade300,
                                              valueColor: AlwaysStoppedAnimation<Color>(Colors.purple.shade400),
                                            ),
                                          ],
                                        ),
                                      ),
                                      SizedBox(width: 16),
                                      Container(
                                        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            colors: [Colors.lightBlue.shade400, Colors.blue.shade600],
                                          ),
                                          borderRadius: BorderRadius.circular(15),
                                        ),
                                        child: Text(
                                          "${submittedRollNumbers.length}/${rollNumbers.length}",
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              SizedBox(height: 20),
                              SizedBox(height: 20),
                              // Category Navigation with modern chips
                              FadeInUp(
                                duration: Duration(milliseconds: 600),
                                child: Container(
                                  height: 50,
                                  child: ListView(
                                    scrollDirection: Axis.horizontal,
                                    children: categories.map((cat) {
                                      return Container(
                                        margin: EdgeInsets.only(right: 12),
                                        child: InkWell(
                                          onTap: () {
                                            Scrollable.ensureVisible(
                                              categoryKeys[cat['id']]!.currentContext!,
                                            );
                                          },
                                          child: Container(
                                            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                            decoration: BoxDecoration(
                                              gradient: LinearGradient(
                                                colors: [Colors.cyan.shade400, Colors.blue.shade600],
                                              ),
                                              borderRadius: BorderRadius.circular(25),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: Colors.blue.withOpacity(0.3),
                                                  blurRadius: 8,
                                                  offset: Offset(0, 3),
                                                ),
                                              ],
                                            ),
                                            child: Center(
                                              child: Text(
                                                cat['category_name'],
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                ),
                              ),
                              SizedBox(height: 24),
                              // Student Selection with modern design
                              FadeInUp(
                                duration: Duration(milliseconds: 700),
                                child: Container(
                                  padding: EdgeInsets.all(20),
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        Colors.white.withOpacity(0.9),
                                        Colors.white.withOpacity(0.7),
                                      ],
                                    ),
                                    borderRadius: BorderRadius.circular(18),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.1),
                                        blurRadius: 10,
                                        offset: Offset(0, 5),
                                      ),
                                    ],
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Container(
                                            padding: EdgeInsets.all(8),
                                            decoration: BoxDecoration(
                                              gradient: LinearGradient(
                                                colors: [Colors.blue.shade400, Colors.blue.shade700],
                                              ),
                                              borderRadius: BorderRadius.circular(10),
                                            ),
                                            child: Icon(Icons.person_search, color: Colors.white, size: 18),
                                          ),
                                          SizedBox(width: 12),
                                          Text(
                                            "Select Student to Evaluate",
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 16,
                                              color: Colors.black87,
                                            ),
                                          ),
                                        ],
                                      ),
                                      SizedBox(height: 16),
                                      InkWell(
                                        onTap: () => _showRollNumberDialog(context),
                                        child: Container(
                                          width: double.infinity,
                                          padding: EdgeInsets.all(16),
                                          decoration: BoxDecoration(
                                            color: Colors.grey.shade50,
                                            borderRadius: BorderRadius.circular(12),
                                            border: Border.all(
                                              color: evaluatedOfError != null 
                                                ? Colors.red.shade300 
                                                : Colors.grey.shade300,
                                              width: 1.5,
                                            ),
                                          ),
                                          child: Row(
                                            children: [
                                              Icon(
                                                Icons.school,
                                                color: selectedRollNumber != null 
                                                  ? Colors.blue.shade600 
                                                  : Colors.grey.shade500,
                                              ),
                                              SizedBox(width: 12),
                                              Expanded(
                                                child: Text(
                                                  selectedRollNumber != null 
                                                    ? '$selectedRollNumber - ${rollNumberToName[selectedRollNumber] ?? 'Unknown'}'
                                                    : "Tap to select student roll number",
                                                  style: TextStyle(
                                                    color: selectedRollNumber != null 
                                                      ? Colors.black87 
                                                      : Colors.grey.shade600,
                                                    fontSize: 14,
                                                    fontWeight: selectedRollNumber != null 
                                                      ? FontWeight.w600 
                                                      : FontWeight.normal,
                                                  ),
                                                ),
                                              ),
                                              Icon(
                                                Icons.arrow_drop_down,
                                                color: Colors.grey.shade600,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      if (evaluatedOfError != null)
                                        Padding(
                                          padding: const EdgeInsets.only(top: 8),
                                          child: Text(
                                            evaluatedOfError!,
                                            style: TextStyle(
                                              color: Colors.red.shade600,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                              SizedBox(height: 24),
                              SizedBox(height: 24),
                              // Categories with modern card design
                              ...categories.map((cat) {
                                final id = cat['id'],
                                    name = cat['category_name'],
                                    marks = cat['marks'],
                                    type = cat['type'];
                                return FadeInUp(
                                  duration: Duration(milliseconds: 800),
                                  child: Container(
                                    key: categoryKeys[id],
                                    margin: EdgeInsets.only(bottom: 20),
                                    padding: EdgeInsets.all(20),
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [
                                          Colors.white.withOpacity(0.9),
                                          Colors.white.withOpacity(0.7),
                                        ],
                                      ),
                                      borderRadius: BorderRadius.circular(18),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.1),
                                          blurRadius: 10,
                                          offset: Offset(0, 5),
                                        ),
                                      ],
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Container(
                                              padding: EdgeInsets.all(8),
                                              decoration: BoxDecoration(
                                                gradient: LinearGradient(
                                                  colors: type == 'text' 
                                                    ? [Colors.indigo.shade400, Colors.indigo.shade600]
                                                    : [Colors.lightBlue.shade400, Colors.blue.shade600],
                                                ),
                                                borderRadius: BorderRadius.circular(10),
                                              ),
                                              child: Icon(
                                                type == 'text' ? Icons.comment : Icons.stars,
                                                color: Colors.white,
                                                size: 18,
                                              ),
                                            ),
                                            SizedBox(width: 12),
                                            Expanded(
                                              child: Text(
                                                type == 'text' ? name : "$name (Max $marks)",
                                                style: TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 16,
                                                  color: Colors.black87,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        SizedBox(height: 16),
                                        if (type == 'text')
                                          Container(
                                            decoration: BoxDecoration(
                                              color: Colors.grey.shade50,
                                              borderRadius: BorderRadius.circular(12),
                                              border: Border.all(color: Colors.grey.shade300),
                                            ),
                                            child: TextFormField(
                                              controller: markControllers[id],
                                              maxLines: 3,
                                              decoration: InputDecoration(
                                                hintText: 'Enter your comment here...',
                                                border: InputBorder.none,
                                                contentPadding: EdgeInsets.all(16),
                                                hintStyle: TextStyle(color: Colors.grey.shade500),
                                              ),
                                              style: TextStyle(fontSize: 14),
                                              autovalidateMode: AutovalidateMode.onUserInteraction,
                                              validator: (v) {
                                                final s = v?.trim() ?? '';
                                                if (s.isEmpty) return 'Comment is required';
                                                if (s.length < 5) return 'Minimum 5 characters required';
                                                return null;
                                              },
                                            ),
                                          )
                                        else
                                          Row(
                                            children: [
                                              Expanded(
                                                flex: 2,
                                                child: Container(
                                                  decoration: BoxDecoration(
                                                    color: Colors.grey.shade50,
                                                    borderRadius: BorderRadius.circular(12),
                                                    border: Border.all(color: Colors.grey.shade300),
                                                  ),
                                                  child: TextFormField(
                                                    controller: markControllers[id],
                                                    keyboardType: TextInputType.numberWithOptions(decimal: true),
                                                    inputFormatters: [
                                                      FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                                                    ],
                                                    decoration: InputDecoration(
                                                      labelText: 'Enter Marks',
                                                      border: InputBorder.none,
                                                      contentPadding: EdgeInsets.all(16),
                                                      labelStyle: TextStyle(color: Colors.grey.shade600),
                                                    ),
                                                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                                                    autovalidateMode: AutovalidateMode.onUserInteraction,
                                                    validator: (v) {
                                                      if (v == null || v.trim().isEmpty)
                                                        return 'Marks required';
                                                      final n = double.tryParse(v);
                                                      if (n == null) return 'Numbers only';
                                                      if (n < 0) return 'Invalid marks';
                                                      if (n > marks) return 'Max $marks';
                                                      return null;
                                                    },
                                                  ),
                                                ),
                                              ),
                                              SizedBox(width: 16),
                                              Expanded(
                                                child: Container(
                                                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                                  decoration: BoxDecoration(
                                                    gradient: LinearGradient(
                                                      colors: [Colors.lightBlue.shade50, Colors.blue.shade100],
                                                    ),
                                                    borderRadius: BorderRadius.circular(12),
                                                    border: Border.all(color: Colors.blue.shade200),
                                                  ),
                                                  child: DropdownButtonHideUnderline(
                                                    child: DropdownButton<int>(
                                                      hint: Text(
                                                        "Quick Select",
                                                        style: TextStyle(
                                                          color: Colors.blue.shade600,
                                                          fontSize: 12,
                                                        ),
                                                      ),
                                                      value: (dropdownValues[id] != null && dropdownValues[id] >= 0 && dropdownValues[id] <= marks) ? dropdownValues[id] : null,
                                                      isExpanded: true,
                                                      icon: Icon(Icons.keyboard_arrow_down, color: Colors.blue.shade600),
                                                      items: List.generate(
                                                        marks + 1,
                                                        (i) => DropdownMenuItem(
                                                          value: i,
                                                          child: Container(
                                                            padding: EdgeInsets.symmetric(vertical: 4),
                                                            child: Text(
                                                              '$i',
                                                              style: TextStyle(
                                                                fontWeight: FontWeight.w600,
                                                                color: Colors.blue.shade700,
                                                              ),
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                      onChanged: (v) {
                                                        setState(() {
                                                          markControllers[id]?.text = v?.toString() ?? '';
                                                          dropdownValues[id] = v;
                                                        });
                                                      },
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                      ],
                                    ),
                                  ),
                                );
                              }).toList(),
                              SizedBox(height: 30),
                              // Submit Button with modern design
                              Center(
                                child: Column(
                                  children: [
                                    FadeInUp(
                                      duration: Duration(milliseconds: 900),
                                      child: Transform.translate(
                                        offset: Offset(_shakeAnimation.value, 0),
                                        child: Container(
                                          width: double.infinity,
                                          height: 60,
                                          child: ElevatedButton(
                                            onPressed: isSubmitting ? null : submitEvaluation,
                                            style: ElevatedButton.styleFrom(
                                              elevation: 0,
                                              backgroundColor: Colors.transparent,
                                              shape: RoundedRectangleBorder(
                                                borderRadius: BorderRadius.circular(30),
                                              ),
                                              padding: EdgeInsets.zero,
                                            ),
                                            child: Ink(
                                              decoration: BoxDecoration(
                                                gradient: LinearGradient(
                                                  colors: isSubmitting
                                                    ? [Colors.grey.shade400, Colors.grey.shade500]
                                                    : [Colors.lightBlue.shade400, Colors.blue.shade600],
                                                  begin: Alignment.centerLeft,
                                                  end: Alignment.centerRight,
                                                ),
                                                borderRadius: BorderRadius.circular(30),
                                                boxShadow: [
                                                  BoxShadow(
                                                    color: (isSubmitting ? Colors.grey : Colors.blue).withOpacity(0.4),
                                                    blurRadius: 15,
                                                    offset: Offset(0, 8),
                                                  ),
                                                ],
                                              ),
                                              child: Container(
                                                alignment: Alignment.center,
                                                child: Row(
                                                  mainAxisAlignment: MainAxisAlignment.center,
                                                  children: [
                                                    if (isSubmitting)
                                                      SizedBox(
                                                        width: 24,
                                                        height: 24,
                                                        child: CircularProgressIndicator(
                                                          strokeWidth: 2,
                                                          color: Colors.white,
                                                        ),
                                                      )
                                                    else
                                                      Icon(
                                                        isOnline ? Icons.send : Icons.save,
                                                        color: Colors.white,
                                                        size: 24,
                                                      ),
                                                    SizedBox(width: 12),
                                                    Text(
                                                      isSubmitting
                                                          ? 'Processing...'
                                                          : isOnline 
                                                            ? 'Submit Evaluation'
                                                            : 'Save Offline',
                                                      style: TextStyle(
                                                        color: Colors.white,
                                                        fontSize: 16,
                                                        fontWeight: FontWeight.bold,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    if (submitError != null)
                                      Container(
                                        margin: EdgeInsets.only(top: 12),
                                        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                        decoration: BoxDecoration(
                                          color: Colors.red.shade50,
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(color: Colors.red.shade200),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.error_outline, color: Colors.red.shade600, size: 16),
                                            SizedBox(width: 8),
                                            Flexible(
                                              child: Text(
                                                submitError!,
                                                style: TextStyle(
                                                  color: Colors.red.shade700,
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              SizedBox(height: 30),
                              // Submitted Evaluations Section with modern design
                              if (submittedEvaluations.isEmpty)
                                FadeInUp(
                                  duration: Duration(milliseconds: 1000),
                                  child: Container(
                                    padding: EdgeInsets.all(24),
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [
                                          Colors.white.withOpacity(0.8),
                                          Colors.white.withOpacity(0.6),
                                        ],
                                      ),
                                      borderRadius: BorderRadius.circular(18),
                                    ),
                                    child: Column(
                                      children: [
                                        Icon(
                                          Icons.assignment_outlined,
                                          size: 48,
                                          color: Colors.grey.shade400,
                                        ),
                                        SizedBox(height: 16),
                                        Text(
                                          "No evaluations submitted yet",
                                          style: TextStyle(
                                            fontSize: 16,
                                            color: Colors.grey.shade600,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        SizedBox(height: 8),
                                        Text(
                                          "Start by selecting a student above",
                                          style: TextStyle(
                                            fontSize: 14,
                                            color: Colors.grey.shade500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                )
                              else ...[
                                SizedBox(height: 24),
                                // Header for submitted evaluations
                                FadeInUp(
                                  duration: Duration(milliseconds: 800),
                                  child: Container(
                                    padding: EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [
                                          Colors.white.withOpacity(0.9),
                                          Colors.white.withOpacity(0.7),
                                        ],
                                      ),
                                      borderRadius: BorderRadius.circular(15),
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          padding: EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                            gradient: LinearGradient(
                                              colors: [Colors.lightBlue.shade400, Colors.blue.shade600],
                                            ),
                                            borderRadius: BorderRadius.circular(10),
                                          ),
                                          child: Icon(Icons.list_alt, color: Colors.white, size: 20),
                                        ),
                                        SizedBox(width: 12),
                                        Expanded(
                                          child: Text(
                                            "Submitted Evaluations",
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 18,
                                              color: Colors.black87,
                                            ),
                                          ),
                                        ),
                                        Container(
                                          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: Colors.blue.shade100,
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          child: Text(
                                            "${filteredEvaluations.length}",
                                            style: TextStyle(
                                              color: Colors.blue.shade700,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                SizedBox(height: 16),
                                // Filter field
                                FadeInUp(
                                  duration: Duration(milliseconds: 850),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.9),
                                      borderRadius: BorderRadius.circular(15),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.1),
                                          blurRadius: 8,
                                          offset: Offset(0, 4),
                                        ),
                                      ],
                                    ),
                                    child: TextField(
                                      controller: filterController,
                                      decoration: InputDecoration(
                                        hintText: "Search by roll number or student name",
                                        border: InputBorder.none,
                                        prefixIcon: Icon(Icons.search, color: Colors.grey.shade600),
                                        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                                        hintStyle: TextStyle(color: Colors.grey.shade500),
                                      ),
                                    ),
                                  ),
                                ),
                                SizedBox(height: 16),
                                // Evaluation cards
                                ...filteredEvaluations.map((eval) {
                                  final studentRoll = eval['evaluation_of_student'];
                                  final studentName = rollNumberToName[studentRoll] ?? 'Unknown';
                                  return FadeInUp(
                                    duration: Duration(milliseconds: 900),
                                    child: Container(
                                      margin: EdgeInsets.only(bottom: 16),
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          colors: [
                                            Colors.white.withOpacity(0.95),
                                            Colors.white.withOpacity(0.85),
                                          ],
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                        ),
                                        borderRadius: BorderRadius.circular(20),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withOpacity(0.1),
                                            blurRadius: 15,
                                            offset: Offset(0, 8),
                                          ),
                                        ],
                                        border: Border.all(
                                          color: Colors.white.withOpacity(0.3),
                                          width: 1,
                                        ),
                                      ),
                                      child: Padding(
                                        padding: EdgeInsets.all(20),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Container(
                                                  padding: EdgeInsets.all(12),
                                                  decoration: BoxDecoration(
                                                    gradient: LinearGradient(
                                                      colors: [Colors.lightBlue.shade400, Colors.blue.shade600],
                                                    ),
                                                    borderRadius: BorderRadius.circular(12),
                                                  ),
                                                  child: Icon(Icons.person, color: Colors.white, size: 20),
                                                ),
                                                SizedBox(width: 16),
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      Text(
                                                        studentRoll,
                                                        style: TextStyle(
                                                          fontWeight: FontWeight.bold,
                                                          fontSize: 16,
                                                          color: Colors.black87,
                                                        ),
                                                      ),
                                                      SizedBox(height: 4),
                                                      Text(
                                                        studentName,
                                                        style: TextStyle(
                                                          fontSize: 14,
                                                          color: Colors.grey.shade600,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                Container(
                                                  decoration: BoxDecoration(
                                                    gradient: LinearGradient(
                                                      colors: [Colors.orange.shade400, Colors.orange.shade600],
                                                    ),
                                                    borderRadius: BorderRadius.circular(12),
                                                  ),
                                                  child: IconButton(
                                                    icon: Icon(Icons.edit, color: Colors.white, size: 20),
                                                    onPressed: () => startEditing(eval),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            SizedBox(height: 16),
                                            Container(
                                              padding: EdgeInsets.all(16),
                                              decoration: BoxDecoration(
                                                color: Colors.grey.shade50,
                                                borderRadius: BorderRadius.circular(12),
                                                border: Border.all(color: Colors.grey.shade200),
                                              ),
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    "Evaluation Details",
                                                    style: TextStyle(
                                                      fontWeight: FontWeight.bold,
                                                      fontSize: 14,
                                                      color: Colors.grey.shade700,
                                                    ),
                                                  ),
                                                  SizedBox(height: 12),
                                                  ...((eval['details'] ?? []) as List).map<Widget>((d) {
                                                    return Padding(
                                                      padding: EdgeInsets.symmetric(vertical: 4),
                                                      child: Row(
                                                        crossAxisAlignment: CrossAxisAlignment.start,
                                                        children: [
                                                          Container(
                                                            padding: EdgeInsets.all(4),
                                                            decoration: BoxDecoration(
                                                              color: Colors.blue.shade100,
                                                              borderRadius: BorderRadius.circular(6),
                                                            ),
                                                            child: Icon(
                                                              Icons.check_circle,
                                                              size: 14,
                                                              color: Colors.blue.shade600,
                                                            ),
                                                          ),
                                                          SizedBox(width: 12),
                                                          Expanded(
                                                            child: RichText(
                                                              text: TextSpan(
                                                                style: TextStyle(
                                                                  fontSize: 14,
                                                                  color: Colors.black87,
                                                                ),
                                                                children: [
                                                                  TextSpan(
                                                                    text: "${d['category_name']}: ",
                                                                    style: TextStyle(fontWeight: FontWeight.w600),
                                                                  ),
                                                                  TextSpan(
                                                                    text: "${d['obtained_marks'] ?? d['comment_text'] ?? ''}",
                                                                    style: TextStyle(fontWeight: FontWeight.normal),
                                                                  ),
                                                                ],
                                                              ),
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    );
                                                  }).toList(),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                }).toList(),
                                SizedBox(height: 24),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}
