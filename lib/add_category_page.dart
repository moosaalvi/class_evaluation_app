// Final Fixed Category Page with Unified Add/Update API
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'dart:convert';

class AddCategoryPage extends StatefulWidget {
  final int assessmentId;
  const AddCategoryPage({super.key, required this.assessmentId});

  @override
  State<AddCategoryPage> createState() => _AddCategoryPageState();
}

class _AddCategoryPageState extends State<AddCategoryPage>
    with SingleTickerProviderStateMixin {
  final TextEditingController _categoryController = TextEditingController();
  final TextEditingController _marksController = TextEditingController();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  String? _selectedType;
  final List<String> _typeOptions = ['text', 'dropdown'];

  List<Map<String, dynamic>> categories = [];
  late final Connectivity _connectivity;
  late final Stream<ConnectivityResult> _connectivityStream;

  bool _isSubmitting = false;
  late AnimationController _shakeController;
  late Animation<double> _offsetAnimation;

  @override
  void initState() {
    super.initState();
    _connectivity = Connectivity();
    _connectivityStream = _connectivity.onConnectivityChanged;
    _connectivityStream.listen((result) {
      if (result != ConnectivityResult.none) {
        _uploadPendingCategories();
      }
    });
    _loadCachedCategories();
    _fetchCategories();

    _shakeController =
        AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    _offsetAnimation = Tween(begin: 0.0, end: 24.0)
        .chain(CurveTween(curve: Curves.elasticIn))
        .animate(_shakeController);
  }

  @override
  void dispose() {
    _shakeController.dispose();
    super.dispose();
  }

  Future<void> _loadCachedCategories() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? cached = prefs.getString('categories_${widget.assessmentId}');
    if (cached != null) {
      final List decoded = jsonDecode(cached);
      setState(() {
        categories = decoded.cast<Map<String, dynamic>>().reversed.toList();
      });
    }
  }

  Future<void> _cacheCategories(List<Map<String, dynamic>> data) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('categories_${widget.assessmentId}', jsonEncode(data));
  }

  Future<void> _fetchCategories() async {
    final url = Uri.parse(
        "https://moosaalvi.pythonanywhere.com/api/assessments/categories/?assessment_id=${widget.assessmentId}");
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final List data = jsonDecode(response.body);
        setState(() {
          categories = data.cast<Map<String, dynamic>>().reversed.toList();
        });
        await _cacheCategories(categories);
      } else {
        Get.snackbar("Error", "Failed to fetch categories");
      }
    } catch (e) {
      Get.snackbar("Offline", "Showing cached categories");
    }
  }

  Future<void> _submitCategory() async {
    if (!_formKey.currentState!.validate()) {
      _shakeController.forward(from: 0.0);
      return;
    }
    setState(() => _isSubmitting = true);
    final newCategory = {
      'assessment': widget.assessmentId,
      'category_name': _categoryController.text.trim(),
      'marks': _selectedType == 'dropdown' ? int.tryParse(_marksController.text.trim()) ?? 0 : 0,
      'type': _selectedType,
      'status': 'E',
    };
    final connectivity = await _connectivity.checkConnectivity();
    if (connectivity == ConnectivityResult.none) {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      List<String> pending = prefs.getStringList('pending_categories') ?? [];
      pending.add(jsonEncode(newCategory));
      await prefs.setStringList('pending_categories', pending);
      Get.snackbar("Saved Locally", "Will upload when internet is available");
      _resetForm();
      setState(() => _isSubmitting = false);
      return;
    }
    await _uploadCategory(newCategory);
    setState(() => _isSubmitting = false);
  }
Future<void> _uploadCategory(Map<String, dynamic> categoryData, {int? id}) async {
  final url = id == null
      ? Uri.parse('https://moosaalvi.pythonanywhere.com/api/assessments/add-category/')
      : Uri.parse('https://moosaalvi.pythonanywhere.com/api/assessments/category/$id/');

  final response = id == null
      ? await http.post(
          url,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(categoryData),
        )
      : await http.put(
          url,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(categoryData),
        );

  if (response.statusCode == 201 || response.statusCode == 200) {
    Get.snackbar("Success", id == null ? "Category added" : "Category updated");
    _resetForm();
    _fetchCategories();
  } else {
    Get.snackbar("Error", "Operation failed");
  }
}



  void _resetForm() {
    _categoryController.clear();
    _marksController.clear();
    setState(() => _selectedType = null);
  }

  Future<void> _uploadPendingCategories() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    List<String> pending = prefs.getStringList('pending_categories') ?? [];
    if (pending.isEmpty) return;
    List<String> remaining = [];
    for (String item in pending) {
      try {
        final categoryData = jsonDecode(item);
        final response = await http.post(
          Uri.parse('https://moosaalvi.pythonanywhere.com/api/assessments/add-category/'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(categoryData),
        );
        if (response.statusCode != 201 && response.statusCode != 200) {
          remaining.add(item);
        }
      } catch (e) {
        remaining.add(item);
      }
    }
    await prefs.setStringList('pending_categories', remaining);
    if (remaining.isEmpty) _fetchCategories();
  }

  
Future<void> _editCategoryDialog(Map<String, dynamic> item) async {
  final TextEditingController editName = TextEditingController(text: item['category_name']);
  final TextEditingController editMarks = TextEditingController(
      text: item['marks'] != null ? item['marks'].toString() : '');
  String? editType = item['type'];

  await showDialog(
    context: context,
    builder: (context) {
      return StatefulBuilder(builder: (context, setState) {
        return AlertDialog(
          title: const Text('Edit Category'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                value: editType,
                items: _typeOptions
                    .map((type) => DropdownMenuItem(value: type, child: Text(type)))
                    .toList(),
                onChanged: (val) => setState(() => editType = val),
                decoration: const InputDecoration(labelText: 'Type'),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: editName,
                decoration: const InputDecoration(labelText: 'Category Name'),
              ),
              const SizedBox(height: 8),
              if (editType == 'dropdown')
                TextFormField(
                  controller: editMarks,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Marks'),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (editName.text.trim().isEmpty) {
                  Get.snackbar("Error", "Category name required");
                  return;
                }
                if (editType == 'dropdown' &&
                    (editMarks.text.trim().isEmpty ||
                        int.tryParse(editMarks.text.trim()) == null)) {
                  Get.snackbar("Error", "Valid marks required for dropdown type");
                  return;
                }

                Navigator.of(context).pop(); // ✅ Close dialog first

                await _uploadCategory({
                  'assessment': widget.assessmentId,
                  'category_name': editName.text.trim(),
                  'marks': editType == 'dropdown' ? int.tryParse(editMarks.text.trim()) ?? 0 : 0,
                  'type': editType,
                  'status': 'E',
                }, id: item['id']);

                Get.snackbar("Updated", "Category updated successfully");
              },
              child: const Text('Save'),
            ),
          ],
        );
      });
    },
  );
}



  Future<void> _deleteCategory(int id) async {
    bool confirmed = false;
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Delete'),
        content: const Text('Are you sure you want to delete this category?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              confirmed = true;
              Navigator.pop(context);
            },
            child: const Text('Delete'),
          )
        ],
      ),
    );
    if (!confirmed) return;
    final url = Uri.parse('https://moosaalvi.pythonanywhere.com/api/assessments/delete-category/$id/');
    await http.delete(url);
    _fetchCategories();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Add Category")),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Form(
              key: _formKey,
              child: Column(
                children: [
                  DropdownButtonFormField<String>(
                    value: _selectedType,
                    items: _typeOptions
                        .map((type) => DropdownMenuItem(value: type, child: Text(type)))
                        .toList(),
                    onChanged: (val) => setState(() => _selectedType = val),
                    decoration: const InputDecoration(labelText: 'Category Type'),
                    validator: (val) => val == null ? 'Please select a type' : null,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _categoryController,
                    decoration: const InputDecoration(labelText: 'Category Name'),
                    validator: (val) => val == null || val.trim().isEmpty ? 'Enter category name' : null,
                  ),
                  if (_selectedType == 'dropdown') const SizedBox(height: 10),
                  if (_selectedType == 'dropdown')
                    TextFormField(
                      controller: _marksController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Marks'),
                      validator: (val) {
                        if (_selectedType == 'dropdown' && (val == null || val.trim().isEmpty)) {
                          return 'Enter marks';
                        }
                        return null;
                      },
                    ),
                  const SizedBox(height: 20),
                  AnimatedBuilder(
                    animation: _shakeController,
                    builder: (context, child) {
                      return Transform.translate(
                        offset: Offset(_offsetAnimation.value, 0),
                        child: ElevatedButton.icon(
                          icon: _isSubmitting
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Icon(Icons.save),
                          label: Text(_isSubmitting ? 'Submitting...' : 'Submit'),
                          onPressed: _isSubmitting ? null : _submitCategory,
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: categories.isEmpty
                  ? const Center(child: Text("No categories added."))
                  : ListView.builder(
                      itemCount: categories.length,
                      itemBuilder: (context, index) {
                        final item = categories[index];
                        return Card(
                          child: ListTile(
                            title: Text(item['category_name']),
                            subtitle: Text(
                              'Type: ${item['type']}${item['type'] == 'dropdown' ? '\nMarks: ${item['marks']}' : ''}\nStatus: ${item['status']}',
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.edit, color: Colors.orange),
                                  onPressed: () => _editCategoryDialog(item),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete, color: Colors.red),
                                  onPressed: () => _deleteCategory(item['id']),
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
