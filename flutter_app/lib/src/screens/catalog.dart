import 'package:flutter/material.dart';

import '../core/duration.dart';

import '../core/api.dart';

import '../core/constants.dart';
import '../core/formatters.dart';
import '../core/models.dart';
import '../core/pricing.dart';
import '../core/session.dart';
import '../core/store.dart';
import '../widgets/common.dart';

/// Catalog screen for both pricing models (`plans`) and add-on services (`addons`).
class CatalogScreen extends StatefulWidget {
  const CatalogScreen({
    super.key,
    required this.session,
    required this.workspace,
    required this.kind,
  });

  final SessionStore session;
  final WorkspaceStore workspace;
  final String kind; // 'plans' | 'addons'

  @override
  State<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends State<CatalogScreen> {
  String _query = '';
  String _status = 'All';

  bool get _isPlans => widget.kind == 'plans';

  List<RecordItem> get _filtered {
    final query = _query.trim().toLowerCase();
    return widget.workspace.listFor(widget.kind).where((item) {
      if (_status != 'All' && item.str('status') != _status) return false;
      if (query.isEmpty) return true;
      return item.str('name').toLowerCase().contains(query) ||
          item.str('description').toLowerCase().contains(query) ||
          (_isPlans ? item.str('mode').contains(query) : item.str('category').toLowerCase().contains(query));
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final items = _filtered;
    return PageScaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(null),
        icon: const Icon(Icons.add),
        label: Text(_isPlans ? 'Add model' : 'Add service'),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 260,
                child: TextField(
                  decoration: inputDecoration(
                      _isPlans ? 'Search models' : 'Search services',
                      prefixIcon: Icons.search),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'All', label: Text('All')),
                  ButtonSegment(value: 'Active', label: Text('Active')),
                  ButtonSegment(value: 'Inactive', label: Text('Inactive')),
                ],
                selected: {_status},
                onSelectionChanged: (s) => setState(() => _status = s.first),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (items.isEmpty)
            EmptyState(
              icon: _isPlans ? Icons.local_dining_outlined : Icons.add_business_outlined,
              title: _isPlans ? 'No pricing models' : 'No services',
              message: _isPlans
                  ? 'Create venue-only, per-plate, combined or fixed package models.'
                  : 'Add decoration, catering, entertainment and other charge lines.',
            )
          else
            for (final item in items) _card(item),
        ],
      ),
    );
  }

  Widget _card(RecordItem item) {
    final subtitle = _isPlans
        ? _planSummary(item)
        : '${inr(item.numOf('price'))} · ${item.str('unit')} · ${item.str('category')}';
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
                  child: Text(item.str('name'),
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                ),
                if (_isPlans)
                  StatusChip(
                      label: planModes
                          .firstWhere(
                            (m) => m.value == item.str('mode'),
                            orElse: () => const PlanMode('?', 'Other', ''),
                          )
                          .label,
                      tone: 'purple'),
                const SizedBox(width: 6),
                StatusChip(
                    label: item.str('status'),
                    tone: statusColorName(item.str('status'))),
              ],
            ),
            const SizedBox(height: 4),
            Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
            if (_isPlans && item.str('description').isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(item.str('description'),
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
            ],
            if (_isPlans) ...[
              const SizedBox(height: 4),
              Text(
                '${item.listOf('menus').length} food menus · ${item.listOf('features').length} inclusions'
                '${item.listOf('eventRates').isNotEmpty ? ' · ${item.listOf('eventRates').length} event rate rules' : ''}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ] else if (item.listOf('features').isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(item.listOf('features').map((f) => f.toString()).join(' · '),
                  style: Theme.of(context).textTheme.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ],
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(onPressed: () => _edit(item), child: const Text('Edit')),
                TextButton(
                  onPressed: () => _delete(item),
                  child: const Text('Delete',
                      style: TextStyle(color: Color(0xFFB3261E))),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _planSummary(RecordItem plan) {
    switch (plan.str('mode')) {
      case 'venue':
        return 'Hall rental only';
      case 'plate':
        return 'Per plate: veg ${inr(plan.numOf('vegRate'))} · non-veg ${inr(plan.numOf('nonVegRate'))}'
            '${plan.numOf('minimumPlates') > 0 ? ' · min ${plan.numOf('minimumPlates').toInt()} plates' : ''}';
      case 'combined':
        return 'Venue + plate: veg ${inr(plan.numOf('vegRate'))} · non-veg ${inr(plan.numOf('nonVegRate'))}';
      case 'fixed':
        return 'Fixed ${inr(plan.numOf('fixedPrice'))}'
            '${plan.numOf('maxGuests') > 0 ? ' · up to ${plan.numOf('maxGuests').toInt()} guests' : ''}';
      default:
        return plan.str('mode');
    }
  }

  Future<void> _delete(RecordItem item) async {
    final ok = await confirmDialog(
      context,
      title: _isPlans ? 'Delete pricing model' : 'Delete service',
      message:
          'Delete "${item.str('name')}"? Saved bookings keep their agreement snapshots.',
      confirmLabel: 'Delete',
    );
    if (!ok || !mounted) return;
    try {
      await widget.workspace.remove(widget.kind, item.id);
      if (mounted) showSnack(context, 'Deleted.');
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    }
  }

  Future<void> _edit(RecordItem? existing) async {
    final result = _isPlans
        ? await showDialog<bool>(
            context: context,
            builder: (_) => Dialog(
              insetPadding: const EdgeInsets.all(18),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720, maxHeight: 800),
                child: PlanEditor(
                  workspace: widget.workspace,
                  existing: existing,
                ),
              ),
            ),
          )
        : await showDialog<bool>(
            context: context,
            builder: (_) => Dialog(
              insetPadding: const EdgeInsets.all(18),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560, maxHeight: 760),
                child: AddonEditor(
                  workspace: widget.workspace,
                  existing: existing,
                ),
              ),
            ),
          );
    if (result == true && mounted) {
      showSnack(context, existing == null ? 'Saved.' : 'Updated.');
    }
  }
}

class PlanEditor extends StatefulWidget {
  const PlanEditor({super.key, required this.workspace, this.existing});

  final WorkspaceStore workspace;
  final RecordItem? existing;

  @override
  State<PlanEditor> createState() => _PlanEditorState();
}

class _PlanEditorState extends State<PlanEditor> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _description;
  late final TextEditingController _terms;
  late final TextEditingController _veg;
  late final TextEditingController _jain;
  late final TextEditingController _nonVeg;
  late final TextEditingController _mixed;
  late final TextEditingController _fixedPrice;
  late final TextEditingController _maxGuests;
  late final TextEditingController _minPlates;
  late final TextEditingController _minFood;
  late final TextEditingController _venueRate;
  late final TextEditingController _advance;
  late final TextEditingController _tax;
  late final TextEditingController _features;
  String _mode = 'venue';
  String _status = 'Active';
  List<FoodMenu> _menus = <FoodMenu>[];
  List<Map<String, dynamic>> _eventRates = <Map<String, dynamic>>[];
  bool _saving = false;

  RecordItem? get _existing => widget.existing;

  @override
  void initState() {
    super.initState();
    final e = _existing;
    _name = TextEditingController(text: e?.str('name') ?? '');
    _description = TextEditingController(text: e?.str('description') ?? '');
    _terms = TextEditingController(text: e?.str('terms') ?? '');
    _veg = TextEditingController(text: e == null ? '' : '${e.numOf('vegRate')}');
    _jain = TextEditingController(text: e == null ? '' : '${e.numOf('jainRate')}');
    _nonVeg = TextEditingController(text: e == null ? '' : '${e.numOf('nonVegRate')}');
    _mixed = TextEditingController(text: e == null ? '' : '${e.numOf('mixedRate')}');
    _fixedPrice =
        TextEditingController(text: e == null ? '' : '${e.numOf('fixedPrice').toInt()}');
    _maxGuests =
        TextEditingController(text: e == null ? '' : '${e.numOf('maxGuests').toInt()}');
    _minPlates =
        TextEditingController(text: e == null ? '' : '${e.numOf('minimumPlates').toInt()}');
    _minFood =
        TextEditingController(text: e == null ? '0' : '${e.numOf('minimumFoodValue')}');
    _venueRate.text = e?.numOfOrNull('venueRate') == null ? '' : '${e!.numOf('venueRate')}';
    _advance.text = e == null ? '30' : '${e.numOf('advancePercent', 30)}';
    _tax.text = e == null ? '0' : '${e.numOf('taxRate')}';
    _features.text =
        (e?.listOf('features') ?? <dynamic>[]).map((f) => f.toString()).join('\n');
    _mode = e?.str('mode', 'venue') ?? 'venue';
    _status = e?.str('status', 'Active') ?? 'Active';
    _menus = (e?.listOf('menus') ?? <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .map(FoodMenu.fromJson)
        .toList();
    _eventRates = (e?.listOf('eventRates') ?? <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .map(Map<String, dynamic>.from)
        .toList();
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _terms.dispose();
    _veg.dispose();
    _jain.dispose();
    _nonVeg.dispose();
    _mixed.dispose();
    _fixedPrice.dispose();
    _maxGuests.dispose();
    _minPlates.dispose();
    _minFood.dispose();
    _venueRate.dispose();
    _advance.dispose();
    _tax.dispose();
    _features.dispose();
    super.dispose();
  }

  num? _num(TextEditingController c) => num.tryParse(c.text.trim());

  List<String> _featureLines() => _features
      .text
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList();

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_name.text.trim().isEmpty || _name.text.trim().length > 120) {
      showSnack(context, 'Enter a name of up to 120 characters.', error: true);
      return;
    }
    if (_mode == 'venue' && _menus.isNotEmpty) {
      showSnack(context,
          'Venue-only billing does not include food. Remove its menus or choose another billing method.',
          error: true);
      return;
    }
    List<FoodMenu> menus;
    List<String> features;
    try {
      menus = _mode == 'venue'
          ? <FoodMenu>[]
          : normalizeMenus(_menus.map((m) => m.toJson()).toList());
      features = normalizeFeatures(_featureLines());
    } on ApiExceptionLike catch (e) {
      showSnack(context, e.message, error: true);
      return;
    }
    final body = <String, dynamic>{
      'name': _name.text.trim(),
      'description': _description.text.trim(),
      'mode': _mode,
      'status': _status,
      'minimumPlates': _num(_minPlates) ?? 0,
      'maxGuests': _num(_maxGuests) ?? 0,
      'minimumFoodValue': _num(_minFood) ?? 0,
      'venueRate': _venueRate.text.trim().isEmpty ? null : (_num(_venueRate) ?? 0),
      'fixedPrice': _num(_fixedPrice) ?? 0,
      'vegRate': _num(_veg) ?? 0,
      'jainRate': _num(_jain) ?? 0,
      'nonVegRate': _num(_nonVeg) ?? 0,
      'mixedRate': _num(_mixed) ?? 0,
      'advancePercent': _num(_advance) ?? 30,
      'taxRate': _num(_tax) ?? 0,
      'features': features,
      'menus': menus.map((m) => m.toJson()).toList(),
      'eventRates': _eventRates,
      'terms': _terms.text.trim(),
    };
    setState(() => _saving = true);
    try {
      if (_existing == null) {
        await widget.workspace.create('plans', body);
      } else {
        await widget.workspace.update('plans', _existing!.id, body);
      }
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showSnack(context, e.message, error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final perPlate = _mode == 'plate' || _mode == 'combined';
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(_existing == null ? 'Add pricing model' : 'Edit pricing model',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 16),
            TextFormField(
              controller: _name,
              decoration: inputDecoration('Name *'),
              validator: (v) => requiredText(v, 'Name', max: 120),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _description,
              maxLines: 2,
              decoration: inputDecoration('Description'),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: StatefulBuilder(builder: (_, setLocal) {
                    return DropdownButtonFormField<String>(
                      initialValue: _mode,
                      decoration: inputDecoration('Billing method *'),
                      items: [
                        for (final m in planModes)
                          DropdownMenuItem(value: m.value, child: Text(m.label)),
                      ],
                      onChanged: (v) => setLocal(() => _mode = v ?? 'venue'),
                    );
                  }),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: StatefulBuilder(builder: (_, setLocal) {
                    return DropdownButtonFormField<String>(
                      initialValue: _status,
                      decoration: inputDecoration('Status *'),
                      items: const [
                        DropdownMenuItem(value: 'Active', child: Text('Active')),
                        DropdownMenuItem(value: 'Inactive', child: Text('Inactive')),
                      ],
                      onChanged: (v) => setLocal(() => _status = v ?? 'Active'),
                    );
                  }),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              planModes
                  .firstWhere((m) => m.value == _mode,
                      orElse: () => const PlanMode('?', '', ''))
                  .description,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            if (perPlate) ...[
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _veg,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: inputDecoration('Vegetarian rate (₹/plate) *'),
                      validator: (v) => numberText(v, 'Vegetarian rate', min: 0.01),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _jain,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: inputDecoration('Jain rate (₹/plate) *'),
                      validator: (v) => numberText(v, 'Jain rate', min: 0.01),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _nonVeg,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: inputDecoration('Non-veg rate (₹/plate) *'),
                      validator: (v) => numberText(v, 'Non-veg rate', min: 0.01),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _mixed,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: inputDecoration('Mixed menu rate (₹/plate) *'),
                      validator: (v) => numberText(v, 'Mixed rate', min: 0.01),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
            if (_mode == 'fixed') ...[
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _fixedPrice,
                      keyboardType: TextInputType.number,
                      decoration: inputDecoration('Package price (₹) *'),
                      validator: (v) => numberText(v, 'Package price', min: 0.01),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _maxGuests,
                      keyboardType: TextInputType.number,
                      decoration: inputDecoration('Included guests *'),
                      validator: (v) =>
                          numberText(v, 'Included guests', min: 1, integer: true),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _minPlates,
                    keyboardType: TextInputType.number,
                    decoration: inputDecoration('Minimum plates',
                        hint: perPlate ? 'Minimum guarantee' : 'Optional'),
                    validator: (v) =>
                        (v ?? '').trim().isEmpty ? null : numberText(v, 'Minimum plates', min: 0, integer: true),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _minFood,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: inputDecoration('Minimum food billing (₹)',
                        hint: '0 = none'),
                    validator: (v) =>
                        (v ?? '').trim().isEmpty ? null : numberText(v, 'Minimum food billing'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _venueRate,
                    keyboardType: TextInputType.number,
                    decoration: inputDecoration('Rental override (₹)',
                        hint: 'Blank = hall rates'),
                    validator: (v) =>
                        (v ?? '').trim().isEmpty ? null : numberText(v, 'Rental override'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _advance,
                    keyboardType: TextInputType.number,
                    decoration: inputDecoration('Advance target (%)'),
                    validator: (v) => numberText(v, 'Advance', min: 0, max: 100),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _tax,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: inputDecoration('Tax (%)'),
                    validator: (v) => numberText(v, 'Tax', min: 0, max: 28),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _section('What’s included (one per line)'),
            TextFormField(
              controller: _features,
              maxLines: 4,
              decoration: inputDecoration('Inclusions',
                  hint: 'Chairs & tables\nSound system…'),
            ),
            const SizedBox(height: 16),
            if (_mode != 'venue') _menusSection() else ...[
              Text('Food menus',
                  style: Theme.of(context)
                      .textTheme
                      .labelLarge
                      ?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text('Venue-only models cannot carry food menus.',
                  style: Theme.of(context).textTheme.bodySmall),
            ],
            const SizedBox(height: 16),
            _eventRatesSection(),
            const SizedBox(height: 16),
            _section('Booking terms'),
            TextFormField(
              controller: _terms,
              maxLines: 3,
              decoration: inputDecoration('Terms', hint: 'Up to 3000 characters'),
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Cancel')),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: Text(_saving ? 'Saving…' : 'Save'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(title,
            style: Theme.of(context)
                .textTheme
                .labelLarge
                ?.copyWith(fontWeight: FontWeight.w800)),
      );

  Widget _menusSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('Food menus (${_menus.length}/4)',
                  style: Theme.of(context)
                      .textTheme
                      .labelLarge
                      ?.copyWith(fontWeight: FontWeight.w800)),
            ),
            DropdownButton<String>(
              hint: const Text('Add menu'),
              underline: const SizedBox.shrink(),
              items: [
                for (final type in foodTypes)
                  if (!_menus.any((m) => m.plateType == type))
                    DropdownMenuItem(value: type, child: Text(type)),
              ],
              onChanged: (type) {
                if (type == null) return;
                setState(() {
                  _menus.add(FoodMenu(
                    plateType: type,
                    sections: [
                      MenuSection(
                          name: type == 'Non-vegetarian' ? 'Starters' : 'Main course',
                          items: <String>[]),
                    ],
                  ));
                });
              },
            ),
          ],
        ),
        for (var i = 0; i < _menus.length; i++) _menuCard(i),
      ],
    );
  }

  Widget _menuCard(int index) {
    final menu = _menus[index];
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(menu.plateType,
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                ),
                IconButton(
                  tooltip: 'Remove menu',
                  icon: const Icon(Icons.delete_outline, size: 20),
                  onPressed: () => setState(() => _menus.removeAt(index)),
                ),
              ],
            ),
            for (var s = 0; s < menu.sections.length; s++) _sectionRow(index, s),
            TextButton.icon(
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Add section'),
              onPressed: () {
                setState(() {
                  menu.sections.add(MenuSection(
                      name: 'Section ${menu.sections.length + 1}', items: <String>[]));
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionRow(int menuIndex, int sectionIndex) {
    final section = _menus[menuIndex].sections[sectionIndex];
    final itemsController = TextEditingController(text: section.items.join('\n'));
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  initialValue: section.name,
                  decoration: const InputDecoration(labelText: 'Section name'),
                  onChanged: (v) => section.name = v,
                ),
              ),
              IconButton(
                tooltip: 'Remove section',
                icon: const Icon(Icons.remove_circle_outline, size: 20),
                onPressed: () {
                  setState(
                      () => _menus[menuIndex].sections.removeAt(sectionIndex));
                },
              ),
            ],
          ),
          const SizedBox(height: 6),
          TextFormField(
            controller: itemsController,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Dishes',
              hintText: 'One dish per line',
            ),
            onChanged: (v) {
              section.items = v
                  .split('\n')
                  .map((l) => l.trim())
                  .where((l) => l.isNotEmpty)
                  .toList();
            },
          ),
        ],
      ),
    );
  }

  Widget _eventRatesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('Event-specific rate rules (${_eventRates.length})',
                  style: Theme.of(context)
                      .textTheme
                      .labelLarge
                      ?.copyWith(fontWeight: FontWeight.w800)),
            ),
            TextButton.icon(
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Add rule'),
              onPressed: () => _editRule(-1),
            ),
          ],
        ),
        for (var i = 0; i < _eventRates.length; i++)
          Card(
            margin: const EdgeInsets.only(bottom: 6),
            child: ListTile(
              dense: true,
              title: Text(_eventRates[i]['eventType']?.toString() ?? ''),
              subtitle: Text(_ruleSummary(_eventRates[i])),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    onPressed: () => _editRule(i),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 18),
                    onPressed: () => setState(() => _eventRates.removeAt(i)),
                  ),
                ],
              ),
            ),
          ),
        if (_eventRates.isEmpty)
          Text('Override rental/package/plate rates for specific event types.',
              style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }

  String _ruleSummary(Map<String, dynamic> rule) {
    final parts = <String>[];
    if (rule['venueRate'] != null) parts.add('rental ${inr((rule['venueRate'] as num).toDouble())}');
    if (rule['fixedPrice'] != null) parts.add('package ${inr((rule['fixedPrice'] as num).toDouble())}');
    if (rule['vegRate'] != null) parts.add('veg ${inr((rule['vegRate'] as num).toDouble())}');
    return parts.isEmpty ? 'No rates set' : parts.join(' · ');
  }

  Future<void> _editRule(int index) async {
    final existing = index >= 0 ? _eventRates[index] : <String, dynamic>{};
    var eventType = (existing['eventType'] as String?) ??
        eventTypes.first;
    final controllers = <String, TextEditingController>{
      for (final key in const [
        'venueRate',
        'fixedPrice',
        'vegRate',
        'jainRate',
        'nonVegRate',
        'mixedRate'
      ])
        key: TextEditingController(
            text: existing[key] == null ? '' : '${existing[key]}'),
    };
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (_, setLocal) {
        return AlertDialog(
          title: Text(index >= 0 ? 'Edit rate rule' : 'Add rate rule'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                StatefulBuilder(builder: (_, setLocal2) {
                  return DropdownButtonFormField<String>(
                    initialValue: eventType,
                    decoration: inputDecoration('Event type'),
                    items: [
                      for (final t in eventTypes)
                        DropdownMenuItem(value: t, child: Text(t)),
                    ],
                    onChanged: (v) => setLocal2(() => eventType = v ?? eventType),
                  );
                }),
                const SizedBox(height: 10),
                for (final key in controllers.keys) ...[
                  TextFormField(
                    controller: controllers[key],
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: inputDecoration(_ruleFieldLabel(key)),
                  ),
                  const SizedBox(height: 8),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Save rule')),
          ],
        );
      }),
    );
    if (saved == true) {
      final rule = <String, dynamic>{'eventType': eventType};
      for (final entry in controllers.entries) {
        final value = entry.value.text.trim();
        if (value.isNotEmpty) {
          final parsed = num.tryParse(value);
          if (parsed != null && parsed > 0) rule[entry.key] = parsed;
        }
      }
      setState(() {
        if (index >= 0) {
          _eventRates[index] = rule;
        } else {
          if (_eventRates.any((r) => r['eventType'] == eventType)) {
            showSnack(context, 'Each event type may appear once.', error: true);
            return;
          }
          _eventRates.add(rule);
        }
      });
    }
    for (final c in controllers.values) {
      c.dispose();
    }
  }

  String _ruleFieldLabel(String key) {
    switch (key) {
      case 'venueRate':
        return 'Rental override (₹)';
      case 'fixedPrice':
        return 'Package price (₹)';
      case 'vegRate':
        return 'Vegetarian rate (₹)';
      case 'jainRate':
        return 'Jain rate (₹)';
      case 'nonVegRate':
        return 'Non-veg rate (₹)';
      default:
        return 'Mixed rate (₹)';
    }
  }
}

class AddonEditor extends StatefulWidget {
  const AddonEditor({super.key, required this.workspace, this.existing});

  final WorkspaceStore workspace;
  final RecordItem? existing;

  @override
  State<AddonEditor> createState() => _AddonEditorState();
}

class _AddonEditorState extends State<AddonEditor> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _description;
  late final TextEditingController _price;
  late final TextEditingController _features;
  String _category = addonCategories.first;
  String _unit = addonUnits.first;
  String _status = 'Active';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.str('name') ?? '');
    _description = TextEditingController(text: e?.str('description') ?? '');
    _price = TextEditingController(text: e == null ? '' : '${e.numOf('price')}');
    _features.text =
        (e?.listOf('features') ?? <dynamic>[]).map((f) => f.toString()).join('\n');
    _category = e?.str('category', addonCategories.first) ?? addonCategories.first;
    _unit = e?.str('unit', addonUnits.first) ?? addonUnits.first;
    _status = e?.str('status', 'Active') ?? 'Active';
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _price.dispose();
    _features.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    List<String> features;
    try {
      features = normalizeFeatures(_features
          .text
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .toList());
    } on ApiExceptionLike catch (e) {
      showSnack(context, e.message, error: true);
      return;
    }
    final body = <String, dynamic>{
      'name': _name.text.trim(),
      'description': _description.text.trim(),
      'price': num.tryParse(_price.text.trim()) ?? 0,
      'category': _category,
      'unit': _unit,
      'status': _status,
      'features': features,
    };
    setState(() => _saving = true);
    try {
      if (widget.existing == null) {
        await widget.workspace.create('addons', body);
      } else {
        await widget.workspace.update('addons', widget.existing!.id, body);
      }
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showSnack(context, e.message, error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.existing == null ? 'Add service' : 'Edit service',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 16),
            TextFormField(
              controller: _name,
              decoration: inputDecoration('Name *'),
              validator: (v) => requiredText(v, 'Name', max: 120),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _description,
              maxLines: 2,
              decoration: inputDecoration('Description'),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _price,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: inputDecoration('Rate (₹) *'),
                    validator: (v) => numberText(v, 'Rate', min: 0.01),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: StatefulBuilder(builder: (_, setLocal) {
                    return DropdownButtonFormField<String>(
                      initialValue: _unit,
                      decoration: inputDecoration('Billing unit *'),
                      items: [
                        for (final u in addonUnits)
                          DropdownMenuItem(value: u, child: Text(u)),
                      ],
                      onChanged: (v) => setLocal(() => _unit = v ?? addonUnits.first),
                    );
                  }),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: StatefulBuilder(builder: (_, setLocal) {
                    return DropdownButtonFormField<String>(
                      initialValue: _category,
                      decoration: inputDecoration('Category *'),
                      items: [
                        for (final c in addonCategories)
                          DropdownMenuItem(value: c, child: Text(c)),
                      ],
                      onChanged: (v) =>
                          setLocal(() => _category = v ?? addonCategories.first),
                    );
                  }),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: StatefulBuilder(builder: (_, setLocal) {
                    return DropdownButtonFormField<String>(
                      initialValue: _status,
                      decoration: inputDecoration('Status *'),
                      items: const [
                        DropdownMenuItem(value: 'Active', child: Text('Active')),
                        DropdownMenuItem(value: 'Inactive', child: Text('Inactive')),
                      ],
                      onChanged: (v) => setLocal(() => _status = v ?? 'Active'),
                    );
                  }),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _features,
              maxLines: 3,
              decoration: inputDecoration('Features (one per line)',
                  hint: 'Setup and dismantling\nOn-site operator…'),
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Cancel')),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: Text(_saving ? 'Saving…' : 'Save'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
