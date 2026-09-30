import 'package:flutter/material.dart';

import '../core/formatters.dart';
import '../core/models.dart';
import '../core/session.dart';
import '../core/store.dart';
import '../widgets/common.dart';

class HallsScreen extends StatefulWidget {
  const HallsScreen({super.key, required this.session, required this.workspace});

  final SessionStore session;
  final WorkspaceStore workspace;

  @override
  State<HallsScreen> createState() => _HallsScreenState();
}

class _HallsScreenState extends State<HallsScreen> {
  String _query = '';
  String _status = 'All';

  static const List<String> _images = <String>[
    'venue.jpg',
    'garden.jpg',
    'terrace.jpg',
  ];

  bool get _canEdit => Perms.canManage(widget.session.user?.role, 'halls');

  List<RecordItem> get _filtered {
    final query = _query.trim().toLowerCase();
    return widget.workspace.halls.where((h) {
      if (_status != 'All' && h.str('status') != _status) return false;
      if (query.isEmpty) return true;
      return h.str('name').toLowerCase().contains(query) ||
          h.str('type').toLowerCase().contains(query) ||
          h.str('description').toLowerCase().contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final halls = _filtered;
    return PageScaffold(
      floatingActionButton: _canEdit
          ? FloatingActionButton.extended(
              onPressed: () => _editHall(null),
              icon: const Icon(Icons.add),
              label: const Text('Add hall'),
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _toolbar(),
          const SizedBox(height: 12),
          if (widget.workspace.loading && halls.isEmpty)
            const LoadingCenter()
          else if (widget.workspace.error != null && halls.isEmpty)
            ErrorBanner(
                message: widget.workspace.error!,
                onRetry: () => widget.workspace.load())
          else if (halls.isEmpty)
            const EmptyState(
              icon: Icons.warehouse_outlined,
              title: 'No halls found',
              message: 'Add your first venue hall to start taking bookings.',
            )
          else
            ResponsiveRecords(
              widthForTable: 920,
              headers: const ['Hall', 'Type', 'Capacity', 'Pricing', 'Status', 'Actions'],
              rows: [
                for (final hall in halls) _tableRow(hall),
              ],
              cardBuilder: (i) => _hallCard(halls[i]),
            ),
        ],
      ),
    );
  }

  Widget _toolbar() {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 260,
          child: TextField(
            decoration: inputDecoration('Search halls', prefixIcon: Icons.search),
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'All', label: Text('All')),
            ButtonSegment(value: 'Available', label: Text('Available')),
            ButtonSegment(value: 'Maintenance', label: Text('Maintenance')),
          ],
          selected: {_status},
          onSelectionChanged: (s) => setState(() => _status = s.first),
        ),
      ],
    );
  }

  List<Widget> _tableRow(RecordItem hall) {
    return [
      Text(hall.str('name'), style: const TextStyle(fontWeight: FontWeight.w700)),
      Text(hall.str('type')),
      Text('${hall.numOf('capacity').toInt()}'),
      Text(inr(hall.numOf('price'))),
      StatusChip(
          label: hall.str('status'), tone: statusColorName(hall.str('status'))),
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_canEdit) ...[
            IconButton(
              tooltip: 'Edit',
              icon: const Icon(Icons.edit_outlined, size: 20),
              onPressed: () => _editHall(hall),
            ),
            IconButton(
              tooltip: 'Delete',
              icon: const Icon(Icons.delete_outline, size: 20),
              onPressed: () => _deleteHall(hall),
            ),
          ] else
            const Text('—'),
        ],
      ),
    ];
  }

  Widget _hallCard(RecordItem hall) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(hall.str('name'),
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                ),
                StatusChip(
                    label: hall.str('status'),
                    tone: statusColorName(hall.str('status'))),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '${hall.str('type')} · capacity ${hall.numOf('capacity').toInt()} · '
              '${inr(hall.numOf('price'))}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (hall.str('description').isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(hall.str('description'),
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
            ],
            if (_canEdit)
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(onPressed: () => _editHall(hall), child: const Text('Edit')),
                  TextButton(
                      onPressed: () => _deleteHall(hall),
                      child: const Text('Delete',
                          style: TextStyle(color: Color(0xFFB3261E)))),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteHall(RecordItem hall) async {
    final ok = await confirmDialog(
      context,
      title: 'Delete hall',
      message: 'Delete "${hall.str('name')}"? Bookings must be removed first.',
      confirmLabel: 'Delete',
    );
    if (!ok || !mounted) return;
    try {
      await widget.workspace.remove('halls', hall.id);
      if (mounted) showSnack(context, 'Hall deleted.');
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    }
  }

  Future<void> _editHall(RecordItem? existing) async {
    final name = TextEditingController(text: existing?.str('name') ?? '');
    final type = ValueNotifier<String>(existing?.str('type', 'Indoor') ?? 'Indoor');
    final capacity =
        TextEditingController(text: existing == null ? '' : '${existing.numOf('capacity').toInt()}');
    final price =
        TextEditingController(text: existing == null ? '' : '${existing.numOf('price').toInt()}');
    final morning = TextEditingController(
        text: existing?.numOfOrNull('morningPrice') == null
            ? ''
            : '${existing!.numOf('morningPrice').toInt()}');
    final afternoon = TextEditingController(
        text: existing?.numOfOrNull('afternoonPrice') == null
            ? ''
            : '${existing!.numOf('afternoonPrice').toInt()}');
    final evening = TextEditingController(
        text: existing?.numOfOrNull('eveningPrice') == null
            ? ''
            : '${existing!.numOf('eveningPrice').toInt()}');
    final status = ValueNotifier<String>(existing?.str('status', 'Available') ?? 'Available');
    final image = ValueNotifier<String>(existing?.str('image', 'venue.jpg') ?? 'venue.jpg');
    final description = TextEditingController(text: existing?.str('description') ?? '');
    final formKey = GlobalKey<FormState>();
    var saving = false;

    final saved = await showAppDialog<bool>(context, builder: (ctx) {
      return StatefulBuilder(builder: (setLocal) {
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(existing == null ? 'Add hall' : 'Edit hall',
                    style: Theme.of(ctx)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 16),
                TextFormField(
                  controller: name,
                  decoration: inputDecoration('Hall name'),
                  validator: (v) => requiredText(v, 'Name'),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: ValueListenableBuilder<String>(
                        valueListenable: type,
                        builder: (_, value, __) => DropdownButtonFormField<String>(
                          initialValue: value,
                          decoration: inputDecoration('Type'),
                          items: [
                            for (final t in const <String>[
                              'Indoor',
                              'Outdoor',
                              'Rooftop',
                              'Banquet',
                              'Other'
                            ])
                              DropdownMenuItem(value: t, child: Text(t)),
                          ],
                          onChanged: (v) => type.value = v ?? 'Indoor',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: capacity,
                        keyboardType: TextInputType.number,
                        decoration: inputDecoration('Capacity (guests)'),
                        validator: (v) =>
                            numberText(v, 'Capacity', min: 1, max: 10000, integer: true),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: price,
                  keyboardType: TextInputType.number,
                  decoration: inputDecoration('Base price per day (₹)'),
                  validator: (v) => numberText(v, 'Price', min: 0),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: morning,
                        keyboardType: TextInputType.number,
                        decoration:
                            inputDecoration('Morning price', hint: 'Optional'),
                        validator: (v) =>
                            (v ?? '').trim().isEmpty ? null : numberText(v, 'Morning price'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: afternoon,
                        keyboardType: TextInputType.number,
                        decoration:
                            inputDecoration('Afternoon price', hint: 'Optional'),
                        validator: (v) =>
                            (v ?? '').trim().isEmpty ? null : numberText(v, 'Afternoon price'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: evening,
                        keyboardType: TextInputType.number,
                        decoration: inputDecoration('Evening price', hint: 'Optional'),
                        validator: (v) =>
                            (v ?? '').trim().isEmpty ? null : numberText(v, 'Evening price'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: ValueListenableBuilder<String>(
                        valueListenable: status,
                        builder: (_, value, __) => DropdownButtonFormField<String>(
                          initialValue: value,
                          decoration: inputDecoration('Status'),
                          items: const [
                            DropdownMenuItem(value: 'Available', child: Text('Available')),
                            DropdownMenuItem(value: 'Maintenance', child: Text('Maintenance')),
                          ],
                          onChanged: (v) => status.value = v ?? 'Available',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ValueListenableBuilder<String>(
                        valueListenable: image,
                        builder: (_, value, __) => DropdownButtonFormField<String>(
                          initialValue: value,
                          decoration: inputDecoration('Image'),
                          items: [
                            for (final img in _images)
                              DropdownMenuItem(value: img, child: Text(img)),
                          ],
                          onChanged: (v) => image.value = v ?? 'venue.jpg',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: description,
                  maxLines: 3,
                  decoration: inputDecoration('Description'),
                ),
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                        onPressed: () => Navigator.of(ctx).pop(false),
                        child: const Text('Cancel')),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: saving
                          ? null
                          : () async {
                              if (!(formKey.currentState?.validate() ?? false)) return;
                              setLocal(() => saving = true);
                              try {
                                final body = <String, dynamic>{
                                  'name': name.text.trim(),
                                  'type': type.value,
                                  'capacity': int.tryParse(capacity.text.trim()) ?? 0,
                                  'price': num.tryParse(price.text.trim()) ?? 0,
                                  'morningPrice': morning.text.trim().isEmpty
                                      ? null
                                      : num.tryParse(morning.text.trim()),
                                  'afternoonPrice': afternoon.text.trim().isEmpty
                                      ? null
                                      : num.tryParse(afternoon.text.trim()),
                                  'eveningPrice': evening.text.trim().isEmpty
                                      ? null
                                      : num.tryParse(evening.text.trim()),
                                  'status': status.value,
                                  'image': image.value,
                                  'description': description.text.trim(),
                                };
                                if (existing == null) {
                                  await widget.workspace.create('halls', body);
                                } else {
                                  await widget.workspace.update(
                                      'halls', existing.id, body);
                                }
                                if (ctx.mounted) Navigator.of(ctx).pop(true);
                              } on ApiException catch (e) {
                                setLocal(() => saving = false);
                                if (ctx.mounted) showSnack(ctx, e.message, error: true);
                              }
                            },
                      child: Text(saving ? 'Saving…' : 'Save'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      });
    });
    if (saved == true && mounted) {
      showSnack(context, existing == null ? 'Hall added.' : 'Hall updated.');
    }
  }
}
