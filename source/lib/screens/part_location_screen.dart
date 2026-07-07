import 'package:flutter/material.dart';
import '../db/db_helper.dart';
import '../models/models.dart';
import '../utils/theme.dart';
import '../widgets/pressable_button.dart';
import '../widgets/app_bottom_nav.dart';
import 'camera_screen.dart';
import '../utils/page_transitions.dart';

class PartLocationScreen extends StatefulWidget {
  final Employee employee;
  final InspectionType type;
  final Aircraft aircraft;
  const PartLocationScreen({
    super.key,
    required this.employee,
    required this.type,
    required this.aircraft,
  });

  @override
  State<PartLocationScreen> createState() => _PartLocationScreenState();
}

class _PartLocationScreenState extends State<PartLocationScreen> {
  List<PartLocation> _locations = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await DBHelper.instance.getPartLocations();
    setState(() {
      _locations = list;
      _loading = false;
    });
  }

  Future<void> _addLocationDialog() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Part Location'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(hintText: 'e.g. Seat Row 12, LH Sidewall'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) {
      final loc = await DBHelper.instance.addPartLocation(name);
      await _load();
      if (mounted) _goNext(loc);
    }
  }

  Future<void> _editLocation(PartLocation loc) async {
    final controller = TextEditingController(text: loc.name);
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Part Location'),
        content: TextField(controller: controller, autofocus: true),
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
    if (action == 'save' && controller.text.trim().isNotEmpty) {
      await DBHelper.instance.updatePartLocation(loc.id!, controller.text.trim());
      await _load();
    } else if (action == 'delete') {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Delete location?'),
          content: Text('Remove "${loc.name}" from the list? Past photo records are kept.'),
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
        await DBHelper.instance.deletePartLocation(loc.id!);
        await _load();
      }
    }
  }

  void _goNext(PartLocation loc) {
    Navigator.of(context).pushReplacement(
      fadeSlideRoute(CameraScreen(
        employee: widget.employee,
        type: widget.type,
        aircraft: widget.aircraft,
        partLocation: loc,
      )),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('${widget.aircraft.regNo} — Part Location')),
      bottomNavigationBar: const AppBottomNav(current: AppTab.none),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.separated(
                      padding: const EdgeInsets.all(12),
                      itemCount: _locations.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (ctx, i) {
                        final l = _locations[i];
                        return Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 6, offset: const Offset(0, 2)),
                            ],
                          ),
                          child: ListTile(
                            leading: CircleAvatar(backgroundColor: kPrimary.withOpacity(0.1), child: Icon(Icons.place_outlined, color: kPrimary)),
                            title: Text(l.name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(icon: const Icon(Icons.edit_outlined, size: 20), onPressed: () => _editLocation(l)),
                                const Icon(Icons.chevron_right),
                              ],
                            ),
                            onTap: () => _goNext(l),
                          ),
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: PressableButton(
                icon: Icons.add_location_alt_rounded,
                label: 'Add New Location',
                height: 60,
                onPressed: _addLocationDialog,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
