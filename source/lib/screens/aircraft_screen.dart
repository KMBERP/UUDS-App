import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../db/db_helper.dart';
import '../models/models.dart';
import '../utils/theme.dart';
import '../widgets/pressable_button.dart';
import '../utils/page_transitions.dart';
import 'part_location_screen.dart';

class AircraftScreen extends StatefulWidget {
  final Employee employee;
  final InspectionType type;
  const AircraftScreen({super.key, required this.employee, required this.type});

  @override
  State<AircraftScreen> createState() => _AircraftScreenState();
}

class _AircraftScreenState extends State<AircraftScreen> {
  List<Aircraft> _aircraft = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await DBHelper.instance.getAircraft();
    setState(() {
      _aircraft = list;
      _loading = false;
    });
  }

  List<TextInputFormatter> get _letterFormatters => [
        FilteringTextInputFormatter.allow(RegExp('[a-zA-Z]')),
        LengthLimitingTextInputFormatter(3),
        TextInputFormatter.withFunction((oldVal, newVal) => TextEditingValue(
              text: newVal.text.toUpperCase(),
              selection: newVal.selection,
            )),
      ];

  Future<void> _addAircraftDialog() async {
    final controller = TextEditingController();
    final letters = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add New Aircraft'),
        content: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('A6-', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(width: 4),
            SizedBox(
              width: 100,
              child: TextField(
                controller: controller,
                autofocus: true,
                maxLength: 3,
                textCapitalization: TextCapitalization.characters,
                style: const TextStyle(fontSize: 20, letterSpacing: 2),
                inputFormatters: _letterFormatters,
                decoration: const InputDecoration(counterText: '', hintText: 'ABC'),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim().toUpperCase()),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (letters != null && letters.length == 3) {
      final regNo = 'A6-$letters';
      final ac = await DBHelper.instance.addAircraft(regNo);
      await _load();
      if (mounted) _goNext(ac);
    } else if (letters != null && letters.isNotEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter exactly 3 letters, e.g. ABC')),
        );
      }
    }
  }

  Future<void> _editAircraft(Aircraft ac) async {
    final currentLetters = ac.regNo.replaceFirst('A6-', '');
    final controller = TextEditingController(text: currentLetters);
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Aircraft'),
        content: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('A6-', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            SizedBox(
              width: 100,
              child: TextField(
                controller: controller,
                autofocus: true,
                maxLength: 3,
                inputFormatters: _letterFormatters,
                decoration: const InputDecoration(counterText: ''),
              ),
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
    if (action == 'save' && controller.text.trim().length == 3) {
      await DBHelper.instance.updateAircraft(ac.id!, 'A6-${controller.text.trim().toUpperCase()}');
      await _load();
    } else if (action == 'delete') {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Delete aircraft?'),
          content: Text('Remove "${ac.regNo}" from the list? Past photo records are kept.'),
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
        await DBHelper.instance.deleteAircraft(ac.id!);
        await _load();
      }
    }
  }

  void _goNext(Aircraft ac) {
    Navigator.of(context).push(
      fadeSlideRoute(PartLocationScreen(employee: widget.employee, type: widget.type, aircraft: ac)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('${widget.type.label} — Select Aircraft')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _aircraft.isEmpty
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: Text(
                              'No aircraft yet.\nTap "Add New Aircraft" below (e.g. A6-ABC).',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.black54, fontSize: 16),
                            ),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(12),
                          itemCount: _aircraft.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (ctx, i) {
                            final a = _aircraft[i];
                            return Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: [
                                  BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 6, offset: const Offset(0, 2)),
                                ],
                              ),
                              child: ListTile(
                                leading: CircleAvatar(backgroundColor: kPrimary.withOpacity(0.1), child: Icon(Icons.flight, color: kPrimary)),
                                title: Text(a.regNo, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(icon: const Icon(Icons.edit_outlined, size: 20), onPressed: () => _editAircraft(a)),
                                    const Icon(Icons.chevron_right),
                                  ],
                                ),
                                onTap: () => _goNext(a),
                              ),
                            );
                          },
                        ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: PressableButton(
                icon: Icons.add_circle_outline_rounded,
                label: 'Add New Aircraft',
                height: 60,
                onPressed: _addAircraftDialog,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
