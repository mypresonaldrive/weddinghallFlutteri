import 'package:flutter/material.dart';

import '../core/api.dart';

import '../core/constants.dart';
import '../core/duration.dart' as dur;
import '../core/formatters.dart';
import '../core/models.dart';
import '../core/pricing.dart';
import '../core/session.dart';
import '../core/store.dart';
import '../widgets/common.dart';

class _AddonSelection {
  _AddonSelection({required this.id, this.selected = false, this.quantity = 1, this.guestsMode = true});
  final String id;
  bool selected;
  num quantity;
  bool guestsMode;
}

class BookingWizard extends StatefulWidget {
  const BookingWizard({
    super.key,
    required this.session,
    required this.workspace,
    this.existing,
    this.initialDate,
  });

  final SessionStore session;
  final WorkspaceStore workspace;
  final RecordItem? existing;
  final String? initialDate;

  @override
  State<BookingWizard> createState() => _BookingWizardState();
}

class _BookingWizardState extends State<BookingWizard> {
  static const List<String> _stepTitles = <String>[
    'Event & duration',
    'Pricing & catering',
    'Extras',
    'Review',
  ];

  int _step = 0;
  bool _saving = false;

  // Step 1
  late final TextEditingController _name;
  late final TextEditingController _guests;
  late final TextEditingController _familyContact;
  late final TextEditingController _familyPhone;
  late final TextEditingController _notes;
  late final TextEditingController _menuNotes;
  late final TextEditingController _opsNotes;
  String _clientId = '';
  String _hallId = '';
  String _date = '';
  String _durationMode = 'full';
  String _endDate = '';
  String _bookingEndTime = '';
  String _time = '18:00';
  String _endTime = '';
  String _baraatTime = '';
  String _muhuratTime = '';
  String _eventType = 'Wedding';
  String _status = 'Confirmed';

  // Step 2
  String _planId = '';
  String _plateType = '';
  final TextEditingController _guaranteed = TextEditingController();
  final TextEditingController _actual = TextEditingController();
  final TextEditingController _discount = TextEditingController();
  final TextEditingController _taxRate = TextEditingController();
  final TextEditingController _advance = TextEditingController();
  final TextEditingController _manualTotal = TextEditingController();

  // Step 3
  final List<_AddonSelection> _addons = <_AddonSelection>[];

  // Computed
  QuoteResult? _quote;
  String? _quoteError;
  AvailabilityResult? _availability;
  bool _availabilityBusy = false;
  String? _availabilityError;

  bool get _isClient => widget.session.user?.isClient == true;
  bool get _isEdit => widget.existing != null;
  bool get _canPrice => !_isClient;
  bool get _editingManual =>
      _isEdit && widget.existing != null && widget.existing!.str('planId').isEmpty;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _name = TextEditingController(text: existing?.str('name') ?? '');
    _guests = TextEditingController(
        text: existing == null ? '100' : '${existing.numOf('guests').toInt()}');
    _familyContact = TextEditingController(text: existing?.str('familyContact') ?? '');
    _familyPhone = TextEditingController(text: existing?.str('familyPhone') ?? '');
    _notes = TextEditingController(text: existing?.str('notes') ?? '');
    _menuNotes = TextEditingController(text: existing?.str('menuNotes') ?? '');
    _opsNotes = TextEditingController(text: existing?.str('operationsNotes') ?? '');
    _clientId = existing?.str('clientId') ?? '';
    _hallId = existing?.str('hallId') ?? '';
    _date = existing?.str('date') ?? widget.initialDate ?? todayIso();
    _durationMode = existing?.str('durationMode', 'full') ?? 'full';
    _endDate = existing?.str('endDate') ?? _date;
    _bookingEndTime = existing?.str('bookingEndTime') ?? '';
    _time = existing?.str('time', '18:00') ?? '18:00';
    _endTime = existing?.str('endTime') ?? '';
    _baraatTime = existing?.str('baraatTime') ?? '';
    _muhuratTime = existing?.str('muhuratTime') ?? '';
    _eventType = existing?.str('type', 'Wedding') ?? 'Wedding';
    _status = existing?.str('status', 'Confirmed') ?? 'Confirmed';
    if (!eventTypes.contains(_eventType)) _eventType = 'Other';
    _planId = existing?.str('planId') ?? '';
    _plateType = existing?.str('plateType') ?? '';
    final guaranteed = existing?.numOfOrNull('guaranteedPlates');
    _guaranteed.text = guaranteed == null ? '' : '${guaranteed.toInt()}';
    _actual.text = existing?.numOfOrNull('actualGuests') == null
        ? ''
        : '${existing!.numOf('actualGuests').toInt()}';
    _discount.text = existing == null ? '0' : '${existing.numOf('discount')}';
    _taxRate.text = existing == null ? '' : '${existing.numOf('taxRate')}';
    _advance.text = existing == null ? '' : '${existing.numOf('advancePercent')}';
    _manualTotal.text = existing == null ? '' : '${existing.numOf('total').toInt()}';
    final existingAddons = existing?.listOf('addOns') ?? <dynamic>[];
    for (final raw in existingAddons) {
      if (raw is Map) {
        final sel = _AddonSelection(
          id: (raw['id'] ?? '').toString(),
          selected: true,
          quantity: (raw['quantity'] as num?) ?? 1,
          guestsMode: raw['quantityMode'] == 'guests',
        );
        _addons.add(sel);
      }
    }
    for (final addon in widget.workspace.addons) {
      if (!_addons.any((a) => a.id == addon.id)) {
        _addons.add(_AddonSelection(id: addon.id));
      }
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _recompute());
  }

  @override
  void dispose() {
    _name.dispose();
    _guests.dispose();
    _familyContact.dispose();
    _familyPhone.dispose();
    _notes.dispose();
    _menuNotes.dispose();
    _opsNotes.dispose();
    _guaranteed.dispose();
    _actual.dispose();
    _discount.dispose();
    _taxRate.dispose();
    _advance.dispose();
    _manualTotal.dispose();
    super.dispose();
  }

  RecordItem? _hall() => widget.workspace.byId('halls', _hallId);

  RecordItem? _plan() => widget.workspace.byId('plans', _planId);

  List<Map<String, dynamic>> _planMaps() =>
      widget.workspace.plans.where((p) => p.str('status') == 'Active').map((p) => p.data).toList();

  List<Map<String, dynamic>> _addonMaps() =>
      widget.workspace.addons.where((a) => a.str('status') == 'Active').map((a) => a.data).toList();

  Map<String, dynamic> _quoteInput() {
    final input = <String, dynamic>{
      'date': _date,
      'durationMode': _durationMode,
      'endDate': _endDate,
      'bookingEndTime': _bookingEndTime,
      'time': _time,
      'type': _eventType,
      'guests': num.tryParse(_guests.text.trim()) ?? 0,
      'planId': _planId,
      'plateType': _plateType,
      'pricingVersion': 2,
      if (_guaranteed.text.trim().isNotEmpty)
        'guaranteedPlates': num.tryParse(_guaranteed.text.trim()) ?? 0,
      if (_actual.text.trim().isNotEmpty)
        'actualGuests': num.tryParse(_actual.text.trim()) ?? 0,
      if (_canPrice) 'discount': num.tryParse(_discount.text.trim()) ?? 0,
      if (_canPrice) 'taxRate': num.tryParse(_taxRate.text.trim()) ?? 0,
      if (_canPrice) 'advancePercent': num.tryParse(_advance.text.trim()) ?? 0,
      'addOns': [
        for (final sel in _addons.where((a) => a.selected))
          <String, dynamic>{
            'id': sel.id,
            'quantity': sel.guestsMode ? null : sel.quantity,
            'quantityMode': sel.guestsMode ? 'guests' : 'manual',
          },
      ],
    };
    return input;
  }

  Future<void> _recompute() async {
    // Quote preview (pure calculation).
    if (_planId.isNotEmpty && _hall() != null) {
      try {
        final quote = priceBooking(
          _quoteInput(),
          plans: _planMaps(),
          addons: _addonMaps(),
          hall: _hall()!.data,
          previous: widget.existing?.data,
          isClient: _isClient,
        );
        setState(() {
          _quote = quote;
          _quoteError = null;
        });
        _applyPlanDefaults();
      } on dur.ApiExceptionLike catch (e) {
        setState(() {
          _quote = null;
          _quoteError = e.message;
        });
      } catch (e) {
        setState(() {
          _quote = null;
          _quoteError = null;
        });
      }
    } else {
      setState(() {
        _quote = null;
        _quoteError = null;
      });
    }
    await _checkAvailability();
  }

  void _applyPlanDefaults() {
    final plan = _plan();
    if (plan == null) return;
    // Fill plan defaults once fields are empty (new bookings).
    if (!_isEdit) {
      if (_taxRate.text.trim().isEmpty) {
        _taxRate.text = '${plan.numOf('taxRate')}';
      }
      if (_advance.text.trim().isEmpty) {
        _advance.text = '${plan.numOf('advancePercent', 30)}';
      }
      if (_plateType.isEmpty && plan.str('mode') != 'venue') {
        final menus = plan.listOf('menus');
        if (menus.isNotEmpty && menus.first is Map) {
          final offered = menus
              .whereType<Map>()
              .map((m) => (m['plateType'] ?? '').toString())
              .toList();
          if (offered.isNotEmpty) _plateType = offered.first;
        } else if (plateTypes.isNotEmpty) {
          _plateType = plateTypes.first;
        }
      }
      if (_guaranteed.text.trim().isEmpty && plan.str('mode') != 'venue') {
        final min = plan.numOf('minimumPlates').toInt();
        if (min > 0) _guaranteed.text = '$min';
      }
    }
  }

  Future<void> _checkAvailability() async {
    if (_date.isEmpty || !dur.validDate(_date)) return;
    if (_durationMode == 'custom' &&
        (_time.isEmpty || _bookingEndTime.isEmpty)) {
      return;
    }
    if ((_durationMode == 'multiple' || _durationMode == 'custom') &&
        _endDate.isEmpty) {
      return;
    }
    setState(() => _availabilityBusy = true);
    final query = <String, String>{
      'date': _date,
      'durationMode': _durationMode,
      if (_durationMode == 'multiple' || _durationMode == 'custom')
        'endDate': _endDate,
      if (_durationMode == 'custom') ...{
        'time': _time,
        'bookingEndTime': _bookingEndTime,
      },
      if (_isEdit) 'exclude': widget.existing!.id,
    };
    try {
      final result = await widget.workspace.availability(query);
      if (!mounted) return;
      setState(() {
        _availability = result;
        _availabilityError = null;
        _availabilityBusy = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _availabilityError = e.message;
        _availabilityBusy = false;
      });
    }
  }

  String? _validateStep(int step) {
    if (step == 0) {
      if (_name.text.trim().isEmpty) return 'Enter the event name.';
      if (_clientId.isEmpty) return 'Choose the client for this booking.';
      if (_hallId.isEmpty) return 'Choose a venue hall.';
      if (!dur.validDate(_date)) return 'Choose a valid event date.';
      if (!RegExp(r'^([01]\d|2[0-3]):[0-5]\d$').hasMatch(_time)) {
        return 'Choose the ceremony start time.';
      }
      if (_durationMode == 'custom' &&
          !RegExp(r'^([01]\d|2[0-3]):[0-5]\d$').hasMatch(_bookingEndTime)) {
        return 'Choose the booking end time for custom timing.';
      }
      if ((_durationMode == 'multiple' || _durationMode == 'custom')) {
        if (!dur.validDate(_endDate)) return 'Choose a valid end date.';
        if (_endDate.compareTo(_date) < 0) return 'End date must be on or after the start date.';
      }
      final guests = num.tryParse(_guests.text.trim());
      final hall = _hall();
      if (guests == null || guests < 1) return 'Enter the expected guest count.';
      if (hall != null && guests > hall.numOf('capacity')) {
        return 'Guest count must be between 1 and ${hall.numOf('capacity').toInt()}.';
      }
      try {
        dur.bookingDuration(_quoteInput());
      } on dur.ApiExceptionLike catch (e) {
        return e.message;
      }
      final availability = _availability;
      final hallStatus = availability == null
          ? null
          : availability.halls.firstWhere(
              (h) => h.id == _hallId,
              orElse: () =>
                  AvailabilityHall(id: _hallId, available: true, reason: ''),
            );
      if (hallStatus != null &&
          !hallStatus.available &&
          hallStatus.reason.isNotEmpty) {
        return '${hallStatus.reason}. Choose another hall or time.';
      }
      return null;
    }
    if (step == 1) {
      if (_planId.isEmpty && !_editingManual) {
        return 'Choose a pricing model.';
      }
      final plan = _plan();
      if (plan != null) {
        final mode = plan.str('mode');
        if (mode == 'plate' || mode == 'combined') {
          final menus = plan.listOf('menus').whereType<Map>().toList();
          final offered = menus.isNotEmpty
              ? menus.map((m) => (m['plateType'] ?? '').toString()).toList()
              : plateTypes;
          if (_plateType.isEmpty || !offered.contains(_plateType)) {
            return 'Choose a meal type offered by this pricing model.';
          }
          final guaranteed = num.tryParse(_guaranteed.text.trim());
          final min = mode == 'plate' || mode == 'combined'
              ? plan.numOf('minimumPlates').toInt()
              : 0;
          final floor = min < 1 ? 1 : min;
          if (guaranteed == null || guaranteed < floor) {
            return 'Minimum guaranteed guests must be at least $floor.';
          }
          final hall = _hall();
          if (hall != null && guaranteed > hall.numOf('capacity')) {
            return 'Guaranteed guests cannot exceed the hall capacity.';
          }
        }
        if (mode == 'fixed' && plan.numOf('maxGuests') > 0) {
          final guests = num.tryParse(_guests.text.trim()) ?? 0;
          if (guests > plan.numOf('maxGuests')) {
            return 'This package covers up to ${plan.numOf('maxGuests').toInt()} guests.';
          }
        }
      }
      if (_canPrice) {
        final discount = num.tryParse(_discount.text.trim());
        if (discount == null || discount < 0) return 'Enter a valid discount.';
        final tax = num.tryParse(_taxRate.text.trim());
        if (tax == null || tax < 0 || tax > 28) return 'Tax must be between 0 and 28.';
        final advance = num.tryParse(_advance.text.trim());
        if (advance == null || advance < 0 || advance > 100) {
          return 'Advance must be between 0 and 100.';
        }
      }
      if (_planId.isEmpty) {
        final total = num.tryParse(_manualTotal.text.trim());
        if (total == null || total < 0) return 'Enter the booking total.';
      }
      return null;
    }
    if (step == 2) {
      final hall = _hall();
      final capacity = hall?.numOf('capacity') ?? 10000;
      for (final sel in _addons.where((a) => a.selected)) {
        if (!sel.guestsMode && (sel.quantity < 1 || sel.quantity > 10000)) {
          final addon = widget.workspace.byId('addons', sel.id);
          return 'Quantity for ${addon?.str('name') ?? 'an add-on'} must be between 1 and 10000.';
        }
        if (sel.guestsMode) {
          final guests = num.tryParse(_guests.text.trim()) ?? 0;
          if (guests > capacity) return 'Guest count exceeds the hall capacity.';
        }
      }
      return null;
    }
    return null;
  }

  void _continue() {
    final error = _validateStep(_step);
    if (error != null) {
      showSnack(context, error, error: true);
      return;
    }
    if (_step < 3) {
      setState(() => _step += 1);
      _recompute();
    } else {
      _save();
    }
  }

  Map<String, dynamic> _payload() {
    final body = <String, dynamic>{
      'name': _name.text.trim(),
      'clientId': _clientId,
      'hallId': _hallId,
      'date': _date,
      'time': _time,
      'guests': num.tryParse(_guests.text.trim()) ?? 0,
      'type': _eventType,
      'status': _isClient ? 'Pending' : _status,
      'durationMode': _durationMode,
      'endDate': _endDate,
      'bookingEndTime': _bookingEndTime,
      'endTime': _endTime,
      'baraatTime': _baraatTime,
      'muhuratTime': _muhuratTime,
      'familyContact': _familyContact.text.trim(),
      'familyPhone': _familyPhone.text.trim(),
      'notes': _notes.text.trim(),
      'menuNotes': _menuNotes.text.trim(),
      'operationsNotes': _opsNotes.text.trim(),
      'planId': _planId,
      'plateType': _plateType,
      if (_guaranteed.text.trim().isNotEmpty)
        'guaranteedPlates': num.tryParse(_guaranteed.text.trim()) ?? 0,
      if (_actual.text.trim().isNotEmpty)
        'actualGuests': num.tryParse(_actual.text.trim()) ?? 0,
      if (_canPrice) 'discount': num.tryParse(_discount.text.trim()) ?? 0,
      if (_canPrice) 'taxRate': num.tryParse(_taxRate.text.trim()) ?? 0,
      if (_canPrice) 'advancePercent': num.tryParse(_advance.text.trim()) ?? 0,
      if (_planId.isNotEmpty) 'pricingVersion': 2,
      'addOns': [
        for (final sel in _addons.where((a) => a.selected))
          <String, dynamic>{
            'id': sel.id,
            'quantity': sel.guestsMode ? (num.tryParse(_guests.text.trim()) ?? 0) : sel.quantity,
            'quantityMode': sel.guestsMode ? 'guests' : 'manual',
          },
      ],
    };
    if (_planId.isNotEmpty && _quote != null) {
      body['total'] = _quote!.total;
    } else if (_planId.isEmpty) {
      body['total'] = num.tryParse(_manualTotal.text.trim()) ?? 0;
    }
    return body;
  }

  Future<void> _save() async {
    final error = _validateStep(0) ??
        _validateStep(1) ??
        _validateStep(2);
    if (error != null) {
      showSnack(context, error, error: true);
      return;
    }
    setState(() => _saving = true);
    try {
      final body = _payload();
      if (_isEdit) {
        await widget.workspace.update('bookings', widget.existing!.id, body);
      } else {
        await widget.workspace.create('bookings', body);
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showSnack(context, e.message, error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PopScope(
      canPop: !_saving,
      child: Scaffold(
        appBar: AppBar(
          title: Text(_isEdit ? 'Edit booking' : 'New booking'),
          actions: [
            TextButton(
              onPressed: _saving ? null : () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: Column(
          children: [
            _stepHeader(scheme),
            const Divider(height: 1),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 900),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 180),
                          child: _stepWidget(),
                        ),
                        const SizedBox(height: 14),
                        _quoteCard(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            child: Row(
              children: [
                if (_step > 0)
                  OutlinedButton.icon(
                    icon: const Icon(Icons.arrow_back, size: 18),
                    label: const Text('Back'),
                    onPressed:
                        _saving ? null : () => setState(() => _step -= 1),
                  )
                else
                  const SizedBox.shrink(),
                const Spacer(),
                FilledButton.icon(
                  icon: Icon(_step == 3 ? Icons.check : Icons.arrow_forward, size: 18),
                  label: Text(_step == 3
                      ? (_saving ? 'Saving…' : (_isEdit ? 'Save changes' : 'Create booking'))
                      : 'Continue'),
                  onPressed: _saving ? null : _continue,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _stepHeader(ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Row(
        children: [
          for (var i = 0; i < _stepTitles.length; i++) ...[
            if (i > 0)
              Expanded(
                child: Container(
                  height: 2,
                  margin: const EdgeInsets.symmetric(horizontal: 6),
                  color: i <= _step ? scheme.primary : scheme.outlineVariant,
                ),
              ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i < _step
                        ? scheme.primary
                        : i == _step
                            ? scheme.primaryContainer
                            : scheme.surfaceContainerHighest,
                  ),
                  child: Center(
                    child: i < _step
                        ? Icon(Icons.check, size: 16, color: scheme.onPrimary)
                        : Text('${i + 1}',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: i == _step
                                  ? scheme.onPrimaryContainer
                                  : scheme.onSurfaceVariant,
                            )),
                  ),
                ),
                if (MediaQuery.sizeOf(context).width >= 640) ...[
                  const SizedBox(width: 6),
                  Text(
                    _stepTitles[i],
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: i == _step ? FontWeight.w800 : FontWeight.w500,
                      color: i <= _step ? scheme.onSurface : scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _stepWidget() {
    switch (_step) {
      case 0:
        return _stepEvent();
      case 1:
        return _stepPricing();
      case 2:
        return _stepExtras();
      default:
        return _stepReview();
    }
  }

  Future<String?> _pickDate(String current) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.tryParse(current) ?? DateTime.now(),
      firstDate: DateTime(2015),
      lastDate: DateTime(2100),
    );
    if (picked == null) return null;
    return '${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
  }

  Future<String?> _pickTime(String current) async {
    final parts = current.split(':');
    final initial = TimeOfDay(
      hour: int.tryParse(parts.isNotEmpty ? parts[0] : '') ?? 18,
      minute: int.tryParse(parts.length > 1 ? parts[1] : '') ?? 0,
    );
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked == null) return null;
    return '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
  }

  Widget _dateField(String label, String value, void Function(String) onPick) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () async {
        final picked = await _pickDate(value);
        if (picked != null) onPick(picked);
      },
      child: InputDecorator(
        decoration: inputDecoration(label, prefixIcon: Icons.calendar_today_outlined),
        child: Text(formatDate(value)),
      ),
    );
  }

  Widget _timeField(String label, String value, void Function(String) onPick,
      {bool required = false}) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () async {
        final picked = await _pickTime(value.isEmpty ? '18:00' : value);
        if (picked != null) onPick(picked);
      },
      child: InputDecorator(
        decoration: inputDecoration(label, prefixIcon: Icons.schedule),
        child: Text(value.isEmpty
            ? (required ? 'Choose time' : 'Not set')
            : timeLabel(value)),
      ),
    );
  }

  Widget _stepEvent() {
    final halls = widget.workspace.halls;
    final clients = widget.workspace.clients;
    final hall = _hall();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Event & duration',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 14),
            TextFormField(
              controller: _name,
              decoration: inputDecoration('Event name *', hint: 'Priya & Arjun'),
              onChanged: (_) => setState(() {}),
              validator: null,
            ),
            const SizedBox(height: 12),
            LayoutBuilder(builder: (context, constraints) {
              final half = constraints.maxWidth > 520;
              final clientField = StatefulBuilder(builder: (_, setLocal) {
                return DropdownButtonFormField<String>(
                  initialValue: _clientId.isEmpty ? null : _clientId,
                  decoration: inputDecoration('Client *', prefixIcon: Icons.person_outline),
                  items: [
                    for (final c in clients)
                      DropdownMenuItem(
                          value: c.id,
                          child: Text(c.str('name'), overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (v) {
                    setLocal(() => _clientId = v ?? '');
                    setState(() {});
                  },
                );
              });
              final hallField = StatefulBuilder(builder: (_, setLocal) {
                return DropdownButtonFormField<String>(
                  initialValue: _hallId.isEmpty ? null : _hallId,
                  decoration: inputDecoration('Hall *', prefixIcon: Icons.warehouse_outlined),
                  items: [
                    for (final h in halls)
                      DropdownMenuItem(
                        value: h.id,
                        child: Text(
                            '${h.str('name')} · cap ${h.numOf('capacity').toInt()}',
                            overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (v) {
                    setLocal(() => _hallId = v ?? '');
                    _recompute();
                    setState(() {});
                  },
                );
              });
              if (half) {
                return Row(
                  children: [
                    Expanded(child: clientField),
                    const SizedBox(width: 12),
                    Expanded(child: hallField),
                  ],
                );
              }
              return Column(children: [clientField, const SizedBox(height: 12), hallField]);
            }),
            if (clients.isEmpty) ...[
              const SizedBox(height: 8),
              const Text('Add a client first from the Clients screen.',
                  style: TextStyle(fontSize: 12.5, color: Color(0xFF9A6700))),
            ],
            const SizedBox(height: 12),
            LayoutBuilder(builder: (context, constraints) {
              final half = constraints.maxWidth > 520;
              final typeField = StatefulBuilder(builder: (_, setLocal) {
                return DropdownButtonFormField<String>(
                  initialValue: _eventType,
                  decoration: inputDecoration('Event type *'),
                  items: [
                    for (final t in eventTypes)
                      DropdownMenuItem(value: t, child: Text(t)),
                  ],
                  onChanged: (v) {
                    setLocal(() => _eventType = v ?? 'Wedding');
                    _recompute();
                  },
                );
              });
              final guestField = TextFormField(
                controller: _guests,
                keyboardType: TextInputType.number,
                decoration: inputDecoration(
                  'Expected guests *',
                  hint: hall == null ? null : 'Hall capacity ${hall.numOf('capacity').toInt()}',
                ),
                onChanged: (_) {
                  _recompute();
                  setState(() {});
                },
              );
              if (half) {
                return Row(
                  children: [
                    Expanded(child: typeField),
                    const SizedBox(width: 12),
                    Expanded(child: guestField),
                  ],
                );
              }
              return Column(children: [typeField, const SizedBox(height: 12), guestField]);
            }),
            const SizedBox(height: 16),
            Text('Date & duration',
                style: Theme.of(context)
                    .textTheme
                    .labelLarge
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            StatefulBuilder(builder: (_, setLocal) {
              return DropdownButtonFormField<String>(
                initialValue: _durationMode,
                decoration: inputDecoration('Booking duration *'),
                items: [
                  for (final option in dur.durationOptions)
                    DropdownMenuItem(
                        value: option.value,
                        child: Text('${option.label} · ${option.hint}')),
                ],
                onChanged: (v) {
                  setLocal(() {
                    _durationMode = v ?? 'full';
                    if (_durationMode != 'multiple' && _durationMode != 'custom') {
                      _endDate = _date;
                    }
                  });
                  _recompute();
                },
              );
            }),
            const SizedBox(height: 12),
            LayoutBuilder(builder: (context, constraints) {
              final half = constraints.maxWidth > 520;
              final widgets = <Widget>[
                _dateField('Event date *', _date, (v) {
                  setState(() {
                    _date = v;
                    if (_durationMode != 'multiple' && _durationMode != 'custom') {
                      _endDate = v;
                    }
                  });
                  _recompute();
                }),
                _timeField(
                    _durationMode == 'custom' ? 'Start time *' : 'Ceremony time *', _time,
                    (v) {
                  setState(() => _time = v);
                  _recompute();
                }, required: true),
              ];
              if (_durationMode == 'multiple' || _durationMode == 'custom') {
                widgets.add(_dateField('End date *', _endDate, (v) {
                  setState(() => _endDate = v);
                  _recompute();
                }));
              }
              if (_durationMode == 'custom') {
                widgets.add(_timeField('End time *', _bookingEndTime, (v) {
                  setState(() => _bookingEndTime = v);
                  _recompute();
                }, required: true));
              }
              if (half) {
                final rows = <Widget>[];
                for (var i = 0; i < widgets.length; i += 2) {
                  rows.add(Row(
                    children: [
                      Expanded(child: widgets[i]),
                      if (i + 1 < widgets.length) ...[
                        const SizedBox(width: 12),
                        Expanded(child: widgets[i + 1]),
                      ] else
                        const Expanded(child: SizedBox()),
                    ],
                  ));
                  rows.add(const SizedBox(height: 12));
                }
                rows.removeLast();
                return Column(children: rows);
              }
              return Column(
                children: [
                  for (var i = 0; i < widgets.length; i++) ...[
                    if (i > 0) const SizedBox(height: 12),
                    widgets[i],
                  ],
                ],
              );
            }),
            if (_durationMode == 'custom' || _durationMode == 'multiple') ...[
              const SizedBox(height: 8),
              Text(
                'Rental days are calculated from the selected interval.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 16),
            _availabilityBox(),
            const SizedBox(height: 16),
            Text('Ceremony details',
                style: Theme.of(context)
                    .textTheme
                    .labelLarge
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            LayoutBuilder(builder: (context, constraints) {
              final row = constraints.maxWidth > 520;
              final fields = <Widget>[
                _timeField('Baraat time', _baraatTime, (v) => setState(() => _baraatTime = v)),
                _timeField('Muhurat time', _muhuratTime, (v) => setState(() => _muhuratTime = v)),
                _timeField('Ceremony end', _endTime, (v) => setState(() => _endTime = v)),
              ];
              if (row) {
                return Row(
                  children: [
                    for (var i = 0; i < fields.length; i++) ...[
                      if (i > 0) const SizedBox(width: 12),
                      Expanded(child: fields[i]),
                    ],
                  ],
                );
              }
              return Column(
                children: [
                  for (var i = 0; i < fields.length; i++) ...[
                    if (i > 0) const SizedBox(height: 12),
                    fields[i],
                  ],
                ],
              );
            }),
            const SizedBox(height: 16),
            LayoutBuilder(builder: (context, constraints) {
              final half = constraints.maxWidth > 520;
              final contact = TextFormField(
                controller: _familyContact,
                decoration: inputDecoration('Family contact name'),
              );
              final phone = TextFormField(
                controller: _familyPhone,
                keyboardType: TextInputType.phone,
                decoration: inputDecoration('Family contact phone'),
              );
              if (half) {
                return Row(
                  children: [
                    Expanded(child: contact),
                    const SizedBox(width: 12),
                    Expanded(child: phone),
                  ],
                );
              }
              return Column(children: [contact, const SizedBox(height: 12), phone]);
            }),
            const SizedBox(height: 12),
            TextFormField(
              controller: _notes,
              maxLines: 2,
              decoration: inputDecoration('Client-facing notes'),
            ),
            if (!_isClient) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: StatefulBuilder(builder: (_, setLocal) {
                      return DropdownButtonFormField<String>(
                        initialValue: _status,
                        decoration: inputDecoration('Status'),
                        items: [
                          for (final s in bookingStatuses)
                            DropdownMenuItem(value: s, child: Text(s)),
                        ],
                        onChanged: (v) => setLocal(() => _status = v ?? 'Confirmed'),
                      );
                    }),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _availabilityBox() {
    if (_availabilityBusy) {
      return const LinearProgressIndicator(minHeight: 3);
    }
    if (_availabilityError != null) {
      return Text(_availabilityError!,
          style: const TextStyle(color: Color(0xFFB3261E), fontSize: 13));
    }
    final availability = _availability;
    if (availability == null) return const SizedBox.shrink();
    final selected = availability.halls.firstWhere(
      (h) => h.id == _hallId,
      orElse: () => AvailabilityHall(id: '', available: true, reason: ''),
    );
    final color = selected.available ? const Color(0xFF1B7F4C) : const Color(0xFFB3261E);
    final others = availability.halls
        .where((h) => h.id != _hallId && h.available)
        .take(3)
        .toList();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withAlpha(70)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(selected.available ? Icons.check_circle_outline : Icons.error_outline,
                  size: 18, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _hallId.isEmpty
                      ? 'Choose a hall to check availability.'
                      : selected.reason,
                  style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 13),
                ),
              ),
              if (_availabilityBusy) const SizedBox(width: 10),
            ],
          ),
          if (!selected.available && others.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final other in others)
                  ActionChip(
                    label: Text(widget.workspace.byId('halls', other.id)?.str('name') ?? other.id,
                        style: const TextStyle(fontSize: 12)),
                    onPressed: () {
                      setState(() => _hallId = other.id);
                      _recompute();
                    },
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _stepPricing() {
    final plans = widget.workspace.plans;
    final activePlans = plans.where((p) => p.str('status') == 'Active').toList();
    final editingManual = _isEdit && widget.existing!.str('planId').isEmpty;
    final plan = _plan();
    final narrow = MediaQuery.sizeOf(context).width < 560;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Pricing model *',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Text(
                  'Totals are recalculated by the server from your tenant catalog when you save.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                for (final candidate in activePlans) _planTile(candidate),
                if (editingManual && _planId.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      'Legacy manual booking — keeping manual pricing.',
                      style: TextStyle(fontSize: 13, color: Color(0xFF9A6700)),
                    ),
                  ),
                if (activePlans.isEmpty)
                  const Text('No active pricing models. Ask the workspace owner to add one.'),
              ],
            ),
          ),
        ),
        if (plan != null) ...[
          const SizedBox(height: 14),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Catering & charges',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 12),
                  if (plan.str('mode') == 'plate' || plan.str('mode') == 'combined') ...[
                    StatefulBuilder(builder: (_, setLocal) {
                      final menus = plan.listOf('menus').whereType<Map>().toList();
                      final offered = menus.isNotEmpty
                          ? menus.map((m) => (m['plateType'] ?? '').toString()).toList()
                          : plateTypes;
                      if (!offered.contains(_plateType) && offered.isNotEmpty) {
                        _plateType = offered.first;
                      }
                      return DropdownButtonFormField<String>(
                        initialValue: offered.contains(_plateType) ? _plateType : null,
                        decoration: inputDecoration('Meal type *'),
                        items: [
                          for (final t in offered) DropdownMenuItem(value: t, child: Text(t)),
                        ],
                        onChanged: (v) {
                          setLocal(() => _plateType = v ?? '');
                          _recompute();
                        },
                      );
                    }),
                    const SizedBox(height: 12),
                    LayoutBuilder(builder: (context, constraints) {
                      final half = constraints.maxWidth > 520;
                      final guaranteed = TextFormField(
                        controller: _guaranteed,
                        keyboardType: TextInputType.number,
                        decoration: inputDecoration(
                          'Minimum guaranteed guests *',
                          hint: 'From ${plan.numOf('minimumPlates').toInt()}',
                        ),
                        onChanged: (_) {
                          _recompute();
                          setState(() {});
                        },
                      );
                      final actual = TextFormField(
                        controller: _actual,
                        keyboardType: TextInputType.number,
                        decoration: inputDecoration('Actual served (optional)',
                            hint: 'Leave blank for estimate billing'),
                        onChanged: (_) {
                          _recompute();
                          setState(() {});
                        },
                      );
                      if (half) {
                        return Row(
                          children: [
                            Expanded(child: guaranteed),
                            const SizedBox(width: 12),
                            Expanded(child: actual),
                          ],
                        );
                      }
                      return Column(children: [
                        guaranteed,
                        const SizedBox(height: 12),
                        actual,
                      ]);
                    }),
                    const SizedBox(height: 8),
                    Text(
                      'Guest-linked billing: extra plates = actual served − guaranteed.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (plan.str('mode') == 'fixed' &&
                      plan.listOf('menus').isNotEmpty) ...[
                    StatefulBuilder(builder: (_, setLocal) {
                      final menus = plan.listOf('menus').whereType<Map>().toList();
                      final offered = menus
                          .map((m) => (m['plateType'] ?? '').toString())
                          .toList();
                      return DropdownButtonFormField<String>(
                        initialValue: offered.contains(_plateType) ? _plateType : null,
                        decoration: inputDecoration('Meal type'),
                        items: [
                          for (final t in offered)
                            DropdownMenuItem(value: t, child: Text(t)),
                        ],
                        onChanged: (v) => setLocal(() => _plateType = v ?? ''),
                      );
                    }),
                    const SizedBox(height: 12),
                  ],
                  if (_canPrice) ...[
                    LayoutBuilder(builder: (context, constraints) {
                      final half = constraints.maxWidth > 520;
                      final discount = TextFormField(
                        controller: _discount,
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                        decoration: inputDecoration('Discount (₹)',
                            hint: 'From subtotal'),
                        onChanged: (_) {
                          _recompute();
                          setState(() {});
                        },
                      );
                      final tax = TextFormField(
                        controller: _taxRate,
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                        decoration: inputDecoration('Tax (%)', hint: '0–28'),
                        onChanged: (_) {
                          _recompute();
                          setState(() {});
                        },
                      );
                      final advance = TextFormField(
                        controller: _advance,
                        keyboardType: TextInputType.number,
                        decoration: inputDecoration('Advance target (%)'),
                        onChanged: (_) {
                          _recompute();
                          setState(() {});
                        },
                      );
                      if (half) {
                        return Row(
                          children: [
                            Expanded(child: discount),
                            const SizedBox(width: 12),
                            Expanded(child: tax),
                            const SizedBox(width: 12),
                            Expanded(child: advance),
                          ],
                        );
                      }
                      return Column(children: [
                        discount,
                        const SizedBox(height: 12),
                        tax,
                        const SizedBox(height: 12),
                        advance,
                      ]);
                    }),
                  ],
                  if (_planId.isEmpty) ...[
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _manualTotal,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: inputDecoration('Manual booking total (₹)'),
                    ),
                  ],
                  if (plan.str('terms').isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest
                            .withAlpha(110),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(plan.str('terms'),
                          style: Theme.of(context).textTheme.bodySmall),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
        if (narrow) const SizedBox(height: 4),
      ],
    );
  }

  Widget _planTile(RecordItem candidate) {
    final selected = _planId == candidate.id;
    final mode = planModes.firstWhere(
      (m) => m.value == candidate.str('mode'),
      orElse: () => const PlanMode('?', 'Pricing', ''),
    );
    final rateSummary = <String>[];
    switch (candidate.str('mode')) {
      case 'venue':
        rateSummary.add('from ${inr(candidate.numOf('price'))}');
        break;
      case 'plate':
      case 'combined':
        if (candidate.numOf('vegRate') > 0) rateSummary.add('veg ${inr(candidate.numOf('vegRate'))}');
        if (candidate.numOf('nonVegRate') > 0) {
          rateSummary.add('non-veg ${inr(candidate.numOf('nonVegRate'))}');
        }
        if (candidate.numOf('minimumPlates') > 0) {
          rateSummary.add('min ${candidate.numOf('minimumPlates').toInt()} plates');
        }
        break;
      case 'fixed':
        rateSummary.add(inr(candidate.numOf('fixedPrice')));
        if (candidate.numOf('maxGuests') > 0) {
          rateSummary.add('up to ${candidate.numOf('maxGuests').toInt()} guests');
        }
        break;
    }
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: selected ? Theme.of(context).colorScheme.primary : Colors.transparent,
          width: 1.6,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          setState(() {
            _planId = candidate.id;
            _plateType = '';
            _guaranteed.clear();
            _taxRate.clear();
            _advance.clear();
          });
          _recompute();
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_off,
                color: Theme.of(context).colorScheme.primary,
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(candidate.str('name'),
                              style: const TextStyle(fontWeight: FontWeight.w800),
                              overflow: TextOverflow.ellipsis),
                        ),
                        const SizedBox(width: 8),
                        StatusChip(label: mode.label, tone: 'purple'),
                      ],
                    ),
                    if (candidate.str('description').isNotEmpty)
                      Text(candidate.str('description'),
                          style: Theme.of(context).textTheme.bodySmall,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                    if (rateSummary.isNotEmpty)
                      Text(rateSummary.join(' · '),
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _stepExtras() {
    final activeAddons =
        widget.workspace.addons.where((a) => a.str('status') == 'Active').toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Add-on services',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(
              'Charge lines only — they do not reserve inventory.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            if (activeAddons.isEmpty)
              const Text('No add-on services in the catalog yet.')
            else
              for (final addon in activeAddons) _addonTile(addon),
            const SizedBox(height: 16),
            TextFormField(
              controller: _menuNotes,
              maxLines: 2,
              decoration: inputDecoration('Menu / catering notes'),
            ),
            if (!_isClient) ...[
              const SizedBox(height: 12),
              TextFormField(
                controller: _opsNotes,
                maxLines: 3,
                decoration: inputDecoration('Private operations notes',
                    hint: 'Not visible to the client'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _addonTile(RecordItem addon) {
    _AddonSelection sel;
    final matches = _addons.where((a) => a.id == addon.id);
    if (matches.isEmpty) {
      sel = _AddonSelection(id: addon.id);
      _addons.add(sel);
    } else {
      sel = matches.first;
    }
    final perGuest = addon.str('unit') == 'per guest';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          CheckboxListTile(
            value: sel.selected,
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(addon.str('name'),
                style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(
                '${inr(addon.numOf('price'))} · ${addon.str('unit')} · ${addon.str('category')}'),
            onChanged: (v) => setState(() => sel.selected = v ?? false),
          ),
          if (sel.selected)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: perGuest
                  ? Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Quantity follows the guest count (v2 billing).',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                        Switch(
                          value: sel.guestsMode,
                          onChanged: (v) => setState(() => sel.guestsMode = v),
                        ),
                      ],
                    )
                  : Row(
                      children: [
                        Text('Quantity', style: Theme.of(context).textTheme.bodySmall),
                        const SizedBox(width: 10),
                        IconButton(
                          icon: const Icon(Icons.remove_circle_outline, size: 20),
                          onPressed: sel.quantity <= 1
                              ? null
                              : () => setState(() => sel.quantity -= 1),
                        ),
                        Text('${sel.quantity}',
                            style: const TextStyle(fontWeight: FontWeight.w800)),
                        IconButton(
                          icon: const Icon(Icons.add_circle_outline, size: 20),
                          onPressed: () => setState(() => sel.quantity += 1),
                        ),
                        const Spacer(),
                        Text(inr(addon.numOf('price') * sel.quantity),
                            style: const TextStyle(fontWeight: FontWeight.w700)),
                      ],
                    ),
            ),
        ],
      ),
    );
  }

  Widget _stepReview() {
    final hall = _hall();
    final plan = _plan();
    final client = widget.workspace.byId('clients', _clientId);
    final selectedAddons = _addons.where((a) => a.selected).toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Review & save',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            _reviewLine('Event', _name.text),
            _reviewLine('Client', client?.str('name') ?? '—'),
            _reviewLine('Hall', hall?.str('name') ?? '—'),
            _reviewLine('Date', formatDate(_date)),
            _reviewLine('Duration', dur.durationDescription(_quoteInput())),
            _reviewLine('Ceremony', timeLabel(_time)),
            _reviewLine('Guests', _guests.text),
            _reviewLine('Type', _eventType),
            _reviewLine('Status', _isClient ? 'Pending (server confirmed)' : _status),
            _reviewLine('Pricing model', plan?.str('name') ?? 'Manual pricing'),
            if (_plateType.isNotEmpty) _reviewLine('Meal type', _plateType),
            if (_guaranteed.text.isNotEmpty)
              _reviewLine('Guaranteed guests', _guaranteed.text),
            if (_actual.text.isNotEmpty) _reviewLine('Actual served', _actual.text),
            if (selectedAddons.isNotEmpty) ...[
              const Divider(),
              Text('Add-ons',
                  style: Theme.of(context)
                      .textTheme
                      .labelLarge
                      ?.copyWith(fontWeight: FontWeight.w800)),
              for (final sel in selectedAddons)
                _reviewLine(
                  widget.workspace.byId('addons', sel.id)?.str('name') ?? sel.id,
                  sel.guestsMode
                      ? '× guests'
                      : '× ${sel.quantity} = ${inr((widget.workspace.byId('addons', sel.id)?.numOf('price') ?? 0) * sel.quantity)}',
                ),
            ],
            const Divider(),
            if (_quote != null) _quoteLines(_quote!, strongTotals: true) else ...[
              _reviewLine('Total', inr(num.tryParse(_manualTotal.text) ?? 0)),
            ],
            const SizedBox(height: 10),
            if (_quoteError != null)
              Text(_quoteError!,
                  style: const TextStyle(color: Color(0xFFB3261E), fontSize: 13)),
            const SizedBox(height: 6),
            Text(
              _isClient
                  ? 'Your request is saved as Pending. The venue confirms the final total using its catalog pricing.'
                  : 'Saving sends the full record to the server, which recomputes the authoritative quote, checks conflicts and enforces payments.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _reviewLine(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(label,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ),
          Expanded(
            child: Text(value.isEmpty ? '—' : value,
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Widget _quoteCard() {
    final quote = _quote;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.calculate_outlined,
                    size: 18, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Live quote estimate',
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.w800)),
                ),
                if (quote != null)
                  Text('Total ${inr(quote.total)}',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                        color: Theme.of(context).colorScheme.primary,
                      )),
              ],
            ),
            if (quote == null && _quoteError == null) ...[
              const SizedBox(height: 8),
              Text(
                _planId.isEmpty
                    ? 'Choose a pricing model to see live totals.'
                    : 'Choose a hall and guests to calculate the quote.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (quote != null) ...[
              const SizedBox(height: 8),
              _quoteLines(quote),
            ],
            if (_quoteError != null) ...[
              const SizedBox(height: 8),
              Text(_quoteError!,
                  style: const TextStyle(color: Color(0xFFB3261E), fontSize: 13)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _quoteLines(QuoteResult quote, {bool strongTotals = false}) {
    final rows = <Widget>[];
    if (quote.venueAmount > 0) {
      rows.add(_moneyLine('Venue rental',
          '${inr(quote.venueAmount)} · ${quote.duration.label}${quote.duration.rentalUnits > 1 ? ' × ${quote.duration.rentalUnits}' : ''}'));
    }
    if (quote.cateringAmount > 0) {
      rows.add(_moneyLine(
          'Catering',
          '${quote.billedPlates.toInt()} plates × ${inr(quote.plateRate)}'
          '${quote.minimumFoodTopUp > 0 ? ' + min food ${inr(quote.minimumFoodTopUp)}' : ''} = ${inr(quote.cateringAmount)}'));
    }
    if (quote.packageAmount > 0) {
      rows.add(_moneyLine('Fixed package', inr(quote.packageAmount)));
    }
    for (final line in quote.addonLines) {
      rows.add(_moneyLine(line.name, '${inr(line.amount)}'));
    }
    rows.add(const Divider());
    rows.add(_moneyLine('Subtotal', inr(quote.subtotal), strong: true));
    if (quote.discount > 0) rows.add(_moneyLine('Discount', '- ${inr(quote.discount)}'));
    if (quote.taxAmount > 0) {
      rows.add(_moneyLine('Tax (${quote.taxRate}%)', inr(quote.taxAmount)));
    }
    rows.add(_moneyLine('Total', inr(quote.total), strong: strongTotals || true));
    rows.add(_moneyLine(
        'Advance target (${quote.advancePercent}%)', inr(quote.advanceAmount)));
    rows.add(Text(
      'Billing basis: ${quote.billingBasis == 'actual' ? 'actual served guests' : quote.billingBasis == 'legacy' ? 'legacy guaranteed + extra plates' : 'estimate from guest count'}'
      '${quote.duration.days > 1 ? ' · ${quote.duration.rentalUnits} rental days' : ''}',
      style: Theme.of(context).textTheme.bodySmall,
    ));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: rows);
  }

  Widget _moneyLine(String label, String value, {bool strong = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: strong
                    ? const TextStyle(fontWeight: FontWeight.w800)
                    : Theme.of(context).textTheme.bodyMedium),
          ),
          Text(value,
              style: TextStyle(fontWeight: strong ? FontWeight.w900 : FontWeight.w600)),
        ],
      ),
    );
  }
}
