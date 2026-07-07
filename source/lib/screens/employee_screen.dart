import 'package:flutter/material.dart';
import '../db/db_helper.dart';
import '../models/models.dart';
import '../utils/theme.dart';
import '../widgets/pressable_button.dart';
import '../widgets/app_bottom_nav.dart';

class EmployeeScreen extends StatefulWidget {
  const EmployeeScreen({super.key});

  @override
  State<EmployeeScreen> createState() => _EmployeeScreenState();
}

class _EmployeeScreenState extends State<EmployeeScreen> {
  List<Employee> _employees = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await DBHelper.instance.getEmployees();
    setState(() {
      _employees = list;
      _loading = false;
    });
  }

  Future<void> _addEmployeeDialog() async {
    final nameController = TextEditingController();
    final idController = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Inspector'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Full name'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: idController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'UUDS ID (optional)', prefixText: 'UUDS-'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Add')),
        ],
      ),
    );
    if (result == true && nameController.text.trim().isNotEmpty) {
      await DBHelper.instance.addEmployee(nameController.text.trim(), idNumber: idController.text.trim());
      await _load();
    }
  }

  Future<void> _editEmployee(Employee emp) async {
    final nameController = TextEditingController(text: emp.name);
    final idController = TextEditingController(text: emp.idNumber);
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Inspector'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameController, autofocus: true, decoration: const InputDecoration(labelText: 'Full name')),
            const SizedBox(height: 10),
            TextField(
              controller: idController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'UUDS ID', prefixText: 'UUDS-'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'delete'),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, 'save'), child: const Text('Save')),
        ],
      ),
    );
    if (action == 'save' && nameController.text.trim().isNotEmpty) {
      await DBHelper.instance.updateEmployee(emp.id!, nameController.text.trim(), idNumber: idController.text.trim());
      await _load();
    } else if (action == 'delete') {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Delete inspector?'),
          content: Text('Remove "${emp.name}" from the list? Past photo records are kept.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete'),
            ),
          ],
        ),
      );
      if (confirm == true) {
        await DBHelper.instance.deleteEmployee(emp.id!);
        await _load();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Manage Inspectors')),
      bottomNavigationBar: const AppBottomNav(current: AppTab.none),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _employees.isEmpty
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: Text(
                              'No inspectors yet.\nTap "Add New Inspector" below.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.black54, fontSize: 16),
                            ),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(12),
                          itemCount: _employees.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (ctx, i) {
                            final e = _employees[i];
                            return Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: [
                                  BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 6, offset: const Offset(0, 2)),
                                ],
                              ),
                              child: ListTile(
                                leading: CircleAvatar(backgroundColor: kPrimary.withOpacity(0.1), child: Icon(Icons.person, color: kPrimary)),
                                title: Text(e.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                                subtitle: Text(e.idNumber.isEmpty ? 'ID Not Provided' : 'UUDS-${e.idNumber}'),
                                trailing: IconButton(icon: const Icon(Icons.edit_outlined, size: 20), onPressed: () => _editEmployee(e)),
                                onTap: () => _editEmployee(e),
                              ),
                            );
                          },
                        ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: PressableButton(
                icon: Icons.person_add_alt_1_rounded,
                label: 'Add New Inspector',
                height: 60,
                onPressed: _addEmployeeDialog,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
