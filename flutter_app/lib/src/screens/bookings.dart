import 'package:flutter/material.dart';

import '../core/api.dart';

import '../core/duration.dart' as dur;
import '../core/formatters.dart';
import '../core/models.dart';
import '../core/session.dart';
import '../core/store.dart';
import '../widgets/common.dart';
import 'booking_wizard.dart';

class BookingsScreen extends StatefulWidget {
  const BookingsScreen({super.key, required this.session, required this.workspace});

  final SessionStore session;
  final WorkspaceStore workspace;

  @override
  State<BookingsScreen> createState() => _BookingsScreenState();
}

class _BookingsScreenState extends State<BookingsScreen> {
  String _query = '';
  String _status = 'All';
  String _hallId = 'All';
  String _sort = 'upcoming';
  DateTime? _from;
  DateTime? _to;

  bool get _canEdit => Perms.canManage(widget.session.user?.role, 'bookings');
  bool get _isClient => widget.session.user?.isClient == true;

  List<RecordItem> get _filtered {
    final query = _query.trim().toLowerCase();
    var items = widget.workspace.bookings.where((b) {
      if (_status != 'All' && b.str('status') != _status) return false;
      if (_hallId != 'All' && b.str('hallId') != _hallId) return false;
      if (_from != null && b.str('date').compareTo(_iso(_from!)) < 0) return false;
      if (_to != null && b.str('date').compareTo(_iso(_to!)) > 0) return false;
      if (query.isEmpty) return true;
      return b.str('name').toLowerCase().contains(query) ||
          b.str('client').toLowerCase().contains(query) ||
          b.str('hall').toLowerCase().contains(query) ||
          b.str('type').toLowerCase().contains(query);
    }).toList();
    switch (_sort) {
      case 'earliest':
        items.sort((a, b) => a.str('date').compareTo(b.str('date')));
        break;
      case 'latest':
        items.sort((a, b) => b.str('date').compareTo(a.str('date')));
        break;
      case 'value':
        items.sort((a, b) => b.numOf('total').compareTo(a.numOf('total')));
        break;
      case 'balance':
        items.sort((a, b) => balanceFor(b, widget.workspace.payments)
            .compareTo(balanceFor(a, widget.workspace.payments)));
        break;
      default:
        items.sort((a, b) {
          final today = todayIso();
          final aUp = a.str('date').compareTo(today) >= 0 && a.str('status') != 'Cancelled';
          final bUp = b.str('date').compareTo(today) >= 0 && b.str('status') != 'Cancelled';
          if (aUp != bUp) return aUp ? -1 : 1;
          return a.str('date').compareTo(b.str('date'));
        });
    }
    return items;
  }

  String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final bookings = _filtered;
    return PageScaffold(
      floatingActionButton: Perms.canBook(widget.session.user?.role)
          ? FloatingActionButton.extended(
              onPressed: () => _openWizard(null),
              icon: const Icon(Icons.add),
              label: const Text('New booking'),
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _toolbar(context),
          const SizedBox(height: 12),
          if (widget.workspace.loading && bookings.isEmpty)
            const LoadingCenter()
          else if (bookings.isEmpty)
            EmptyState(
              icon: Icons.event_note_outlined,
              title: _isClient ? 'No bookings yet' : 'No bookings found',
              message: _isClient
                  ? 'Request a booking and the venue will confirm availability.'
                  : 'Create your first booking to get started.',
              action: Perms.canBook(widget.session.user?.role)
                  ? FilledButton(
                      onPressed: () => _openWizard(null), child: const Text('New booking'))
                  : null,
            )
          else
            ResponsiveRecords(
              widthForTable: 1120,
              headers: const [
                'Event',
                'Date & duration',
                'Hall / client',
                'Guests',
                'Total / balance',
                'Status',
                'Actions',
              ],
              rows: [
                for (final booking in bookings) _tableRow(booking),
              ],
              cardBuilder: (i) => _bookingCard(bookings[i]),
            ),
        ],
      ),
    );
  }

  Widget _toolbar(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 230,
          child: TextField(
            decoration: inputDecoration('Search events', prefixIcon: Icons.search),
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
        SizedBox(
          width: 150,
          child: DropdownButtonFormField<String>(
            initialValue: _status,
            decoration: inputDecoration('Status'),
            items: [
              const DropdownMenuItem(value: 'All', child: Text('All statuses')),
              for (final s in const <String>['Confirmed', 'Pending', 'Completed', 'Cancelled'])
                DropdownMenuItem(value: s, child: Text(s)),
            ],
            onChanged: (v) => setState(() => _status = v ?? 'All'),
          ),
        ),
        if (!_isClient && widget.workspace.halls.isNotEmpty)
          SizedBox(
            width: 170,
            child: DropdownButtonFormField<String>(
              initialValue: _hallId,
              decoration: inputDecoration('Venue'),
              items: [
                const DropdownMenuItem(value: 'All', child: Text('All halls')),
                for (final h in widget.workspace.halls)
                  DropdownMenuItem(value: h.id, child: Text(h.str('name'))),
              ],
              onChanged: (v) => setState(() => _hallId = v ?? 'All'),
            ),
          ),
        SizedBox(
          width: 170,
          child: DropdownButtonFormField<String>(
            initialValue: _sort,
            decoration: inputDecoration('Sort'),
            items: const [
              DropdownMenuItem(value: 'upcoming', child: Text('Upcoming first')),
              DropdownMenuItem(value: 'earliest', child: Text('Earliest date')),
              DropdownMenuItem(value: 'latest', child: Text('Latest date')),
              DropdownMenuItem(value: 'value', child: Text('Booking value')),
              DropdownMenuItem(value: 'balance', child: Text('Balance due')),
            ],
            onChanged: (v) => setState(() => _sort = v ?? 'upcoming'),
          ),
        ),
        OutlinedButton.icon(
          icon: const Icon(Icons.date_range_outlined, size: 18),
          label: Text(_from == null
              ? 'From date'
              : '${formatDateShort(_iso(_from!))} → ${_to == null ? '…' : formatDateShort(_iso(_to!))}'),
          onPressed: () => _pickRange(),
        ),
        if (_query.isNotEmpty ||
            _status != 'All' ||
            _hallId != 'All' ||
            _from != null ||
            _to != null)
          TextButton(
            onPressed: () => setState(() {
              _query = '';
              _status = 'All';
              _hallId = 'All';
              _from = null;
              _to = null;
            }),
            child: const Text('Clear filters'),
          ),
        Text('${_filtered.length} bookings',
            style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }

  Future<void> _pickRange() async {
    final from = await showDatePicker(
      context: context,
      initialDate: _from ?? DateTime.now(),
      firstDate: DateTime(2015),
      lastDate: DateTime(2100),
    );
    if (from == null || !mounted) return;
    final to = await showDatePicker(
      context: context,
      initialDate: _to ?? from,
      firstDate: from,
      lastDate: DateTime(2100),
    );
    setState(() {
      _from = from;
      _to = to;
    });
  }

  Widget _durationText(RecordItem booking) {
    final map = Map<String, dynamic>.from(booking.data);
    final text = dur.durationDescription(map);
    return Text(text, style: Theme.of(context).textTheme.bodySmall);
  }

  List<Widget> _tableRow(RecordItem booking) {
    final balance = balanceFor(booking, widget.workspace.payments);
    return [
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(booking.str('name'), style: const TextStyle(fontWeight: FontWeight.w700)),
          Text(booking.str('type'), style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(formatDate(booking.str('date')),
              style: const TextStyle(fontWeight: FontWeight.w600)),
          _durationText(booking),
        ],
      ),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(booking.str('hall')),
          Text(booking.str('client'), style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
      Text('${booking.numOf('guests').toInt()}'),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(inr(booking.numOf('total')),
              style: const TextStyle(fontWeight: FontWeight.w700)),
          if (balance > 0.009)
            Text('bal ${inr(balance)}',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: const Color(0xFF9A6700))),
        ],
      ),
      StatusChip(
          label: booking.str('status'), tone: statusColorName(booking.str('status'))),
      _actions(booking),
    ];
  }

  Widget _bookingCard(RecordItem booking) {
    final balance = balanceFor(booking, widget.workspace.payments);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _openDetail(booking),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(booking.str('name'),
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  ),
                  StatusChip(
                      label: booking.str('status'),
                      tone: statusColorName(booking.str('status'))),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                  '${formatDate(booking.str('date'))} · ${booking.str('hall')} · '
                  '${booking.str('guests')} guests'),
              _durationText(booking),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: Text(
                        '${inr(booking.numOf('total'))}'
                        '${balance > 0.009 ? ' · balance ${inr(balance)}' : ' · settled'}',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                  TextButton(
                    onPressed: () => _openDetail(booking),
                    child: const Text('Open'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _actions(RecordItem booking) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Open',
          icon: const Icon(Icons.open_in_new, size: 20),
          onPressed: () => _openDetail(booking),
        ),
        if (_canEdit)
          IconButton(
            tooltip: 'Edit',
            icon: const Icon(Icons.edit_outlined, size: 20),
            onPressed: () => _openWizard(booking),
          ),
        if (_canEdit)
          IconButton(
            tooltip: 'Delete',
            icon: const Icon(Icons.delete_outline, size: 20),
            onPressed: () => _delete(booking),
          ),
      ],
    );
  }

  Future<void> _delete(RecordItem booking) async {
    final ok = await confirmDialog(
      context,
      title: 'Delete booking',
      message:
          'Delete "${booking.str('name')}" on ${formatDate(booking.str('date'))}? Its recorded payments are removed too.',
      confirmLabel: 'Delete',
    );
    if (!ok || !mounted) return;
    try {
      await widget.workspace.remove('bookings', booking.id);
      if (mounted) showSnack(context, 'Booking deleted.');
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    }
  }

  Future<void> _openWizard(RecordItem? existing) async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => BookingWizard(
          session: widget.session,
          workspace: widget.workspace,
          existing: existing,
        ),
      ),
    );
    if (result == true && mounted) {
      showSnack(context,
          existing == null ? 'Booking created.' : 'Booking updated.');
    }
  }

  Future<void> _openDetail(RecordItem booking) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BookingDetailScreen(
          session: widget.session,
          workspace: widget.workspace,
          bookingId: booking.id,
        ),
      ),
    );
  }
}

class BookingDetailScreen extends StatelessWidget {
  const BookingDetailScreen({
    super.key,
    required this.session,
    required this.workspace,
    required this.bookingId,
  });

  final SessionStore session;
  final WorkspaceStore workspace;
  final String bookingId;

  @override
  Widget build(BuildContext context) {
    final booking = workspace.byId('bookings', bookingId);
    if (booking == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Booking')),
        body: const EmptyState(
            icon: Icons.event_busy, title: 'Booking not found', message: 'It may have been deleted.'),
      );
    }
    final canEdit = Perms.canManage(session.user?.role, 'bookings');

    return Scaffold(
      appBar: AppBar(
        title: Text(booking.str('name')),
        actions: [
          if (canEdit)
            IconButton(
              tooltip: 'Edit booking',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () async {
                final ok = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                    builder: (_) => BookingWizard(
                      session: session,
                      workspace: workspace,
                      existing: booking,
                    ),
                  ),
                );
                if (ok == true) (context as Element).markNeedsBuild();
              },
            ),
          const SizedBox(width: 6),
        ],
      ),
      body: ListenableBuilder(
        listenable: workspace,
        builder: (context, _) {
          final current = workspace.byId('bookings', bookingId);
          if (current == null) {
            return const EmptyState(
                icon: Icons.event_busy,
                title: 'Booking deleted',
                message: 'This booking no longer exists.');
          }
          final currentPayments = workspace.payments
              .where((p) => p.str('bookingId') == bookingId)
              .toList();
          final currentPaid =
              currentPayments.fold<double>(0, (s, p) => s + p.numOf('amount').toDouble());
          final currentTotal = current.numOf('total').toDouble();
          final quote = current.data['quote'] is Map
              ? Map<String, dynamic>.from(current.data['quote'] as Map)
              : null;
          final planId = current.str('planId');
          final plan = planId.isEmpty ? null : workspace.byId('plans', planId);
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 980),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        StatusChip(
                            label: current.str('status'),
                            tone: statusColorName(current.str('status'))),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                              '${current.str('type')} · ${formatDate(current.str('date'))}',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w800)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    LayoutBuilder(builder: (context, constraints) {
                      final wide = constraints.maxWidth >= 760;
                      final details = _detailsCard(context, current, plan);
                      final money = _moneyCard(
                          context, current, quote, currentPaid, currentTotal,
                          payments: currentPayments);
                      if (wide) {
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: details),
                            const SizedBox(width: 14),
                            Expanded(child: money),
                          ],
                        );
                      }
                      return Column(children: [details, const SizedBox(height: 14), money]);
                    }),
                    const SizedBox(height: 14),
                    _paymentsCard(context, currentPayments, canEdit),
                    const SizedBox(height: 14),
                    if (current.str('notes').isNotEmpty ||
                        current.str('menuNotes').isNotEmpty ||
                        current.str('operationsNotes').isNotEmpty)
                      _notesCard(context, current),
                  ],
                ),
              ),
            ),
          );
        },
      ),
      bottomNavigationBar: ListenableBuilder(
        listenable: workspace,
        builder: (context, _) {
          final current = workspace.byId('bookings', bookingId);
          if (current == null) return const SizedBox.shrink();
          final paid = workspace.payments
              .where((p) => p.str('bookingId') == bookingId)
              .fold<double>(0, (s, p) => s + p.numOf('amount').toDouble());
          final total = current.numOf('total').toDouble();
          final balance = total - paid;
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Paid ${inr(paid)} of ${inr(total)}'
                      '${balance > 0.009 ? ' · balance ${inr(balance)}' : ' · fully paid'}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  if (canEdit)
                    FilledButton.icon(
                      icon: const Icon(Icons.add_card_outlined, size: 18),
                      label: const Text('Record payment'),
                      onPressed: () => _quickPayment(context, current, balance),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _detailsCard(BuildContext context, RecordItem booking, RecordItem? plan) {
    final entries = <MapEntry<String, String>>[
      MapEntry('Client', booking.str('client')),
      MapEntry('Hall', booking.str('hall')),
      MapEntry('Guests', '${booking.numOf('guests').toInt()}'),
      MapEntry('Duration', dur.durationDescription(Map<String, dynamic>.from(booking.data))),
      MapEntry('Ceremony start', timeLabel(booking.str('time'))),
      if (booking.str('endTime').isNotEmpty)
        MapEntry('Ceremony end', timeLabel(booking.str('endTime'))),
      if (booking.str('baraatTime').isNotEmpty)
        MapEntry('Baraat', timeLabel(booking.str('baraatTime'))),
      if (booking.str('muhuratTime').isNotEmpty)
        MapEntry('Muhurat', timeLabel(booking.str('muhuratTime'))),
      if (plan != null) MapEntry('Pricing model', plan.str('name')),
      if (booking.str('plateType').isNotEmpty)
        MapEntry('Meal type', booking.str('plateType')),
      if (booking.str('familyContact').isNotEmpty)
        MapEntry('Family contact',
            '${booking.str('familyContact')} ${booking.str('familyPhone')}'.trim()),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Event details',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            for (final entry in entries)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 130,
                      child: Text(entry.key,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                    ),
                    Expanded(
                        child: Text(entry.value,
                            style: const TextStyle(fontWeight: FontWeight.w600))),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _moneyCard(
    BuildContext context,
    RecordItem booking,
    Map<String, dynamic>? quote,
    double paid,
    double total, {
    required List<RecordItem> payments,
  }) {
    final lines = <Widget>[];
    if (quote != null) {
      final venue = (quote['venueAmount'] as num?) ?? 0;
      final catering = (quote['cateringAmount'] as num?) ?? 0;
      final package = (quote['packageAmount'] as num?) ?? 0;
      final addons = (quote['addonAmount'] as num?) ?? 0;
      final discount = (quote['discount'] as num?) ?? 0;
      final tax = (quote['taxAmount'] as num?) ?? 0;
      final taxRate = (quote['taxRate'] as num?) ?? 0;
      final advance = (quote['advanceAmount'] as num?) ?? 0;
      if (venue.toDouble() > 0) {
        lines.add(_line(context, 'Venue rental', inr(venue)));
      }
      if (catering.toDouble() > 0) {
        lines.add(_line(context, 'Catering', inr(catering)));
      }
      if (package.toDouble() > 0) {
        lines.add(_line(context, 'Package', inr(package)));
      }
      if (addons.toDouble() > 0) {
        lines.add(_line(context, 'Add-on services', inr(addons)));
      }
      final subtotal = (quote['subtotal'] as num?) ?? 0;
      lines.add(const Divider());
      lines.add(_line(context, 'Subtotal', inr(subtotal)));
      if (discount.toDouble() > 0) {
        lines.add(_line(context, 'Discount', '- ${inr(discount)}'));
      }
      if (tax.toDouble() > 0) {
        lines.add(_line(context, 'Tax (${taxRate}% )'.replaceAll(' )', ')'), inr(tax)));
      }
      final addonLines = quote['addonLines'];
      if (addonLines is List) {
        for (final raw in addonLines) {
          if (raw is Map) {
            lines.add(_line(
                context,
                '${raw['name']} × ${raw['quantity']}',
                inr(((raw['amount'] as num?) ?? 0).toDouble())));
          }
        }
      }
      if (advance.toDouble() > 0) {
        lines.add(_line(context, 'Advance due (${quote['advancePercent'] ?? ''}%)',
            inr(advance)));
      }
    }
    final balance = total - paid;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Charges & payments',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            ...lines,
            if (lines.isNotEmpty) const SizedBox(height: 4),
            _line(context, 'Booking total', inr(total), strong: true),
            _line(context, 'Received', inr(paid)),
            _line(
              context,
              balance > 0.009 ? 'Balance due' : 'Status',
              balance > 0.009 ? inr(balance) : 'Fully paid',
              strong: true,
              color: balance > 0.009 ? const Color(0xFF9A6700) : const Color(0xFF1B7F4C),
            ),
          ],
        ),
      ),
    );
  }

  Widget _line(BuildContext context, String label, String value,
      {bool strong = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: strong
                    ? const TextStyle(fontWeight: FontWeight.w800)
                    : Theme.of(context).textTheme.bodyMedium),
          ),
          Text(value,
              style: TextStyle(
                fontWeight: strong ? FontWeight.w800 : FontWeight.w600,
                color: color,
              )),
        ],
      ),
    );
  }

  Widget _paymentsCard(
      BuildContext context, List<RecordItem> payments, bool canEdit) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Payment history',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            if (payments.isEmpty)
              const Text('No payments recorded yet.')
            else
              for (final p in payments)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: const Icon(Icons.receipt_long_outlined),
                  title: Text('${inr(p.numOf('amount'))} · ${p.str('method')}',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(
                      '${formatDate(p.str('date'))}'
                      '${p.str('reference').isEmpty ? '' : ' · ref ${p.str('reference')}'}'),
                ),
          ],
        ),
      ),
    );
  }

  Widget _notesCard(BuildContext context, RecordItem booking) {
    final rows = <MapEntry<String, String>>[
      if (booking.str('notes').isNotEmpty) MapEntry('Client notes', booking.str('notes')),
      if (booking.str('menuNotes').isNotEmpty)
        MapEntry('Menu notes', booking.str('menuNotes')),
      if (booking.str('operationsNotes').isNotEmpty)
        MapEntry('Operations (private)', booking.str('operationsNotes')),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Notes',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            for (final row in rows)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(row.key,
                        style: Theme.of(context)
                            .textTheme
                            .labelMedium
                            ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                    Text(row.value),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _quickPayment(BuildContext context, RecordItem booking, double balance) async {
    if (balance <= 0.009) {
      showSnack(context, 'This booking is fully paid.');
      return;
    }
    // Reuse the payments screen flow by deep-linking is unnecessary; a compact
    // prompt keeps the detail page focused.
    final controller = TextEditingController(text: balance.toStringAsFixed(0));
    final amount = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Record payment'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: inputDecoration('Amount (₹) — balance ${inr(balance)}'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
              child: const Text('Save')),
        ],
      ),
    );
    if (amount == null || amount.isEmpty) return;
    final parsed = num.tryParse(amount);
    if (parsed == null || parsed <= 0) {
      showSnack(context, 'Enter a valid amount.', error: true);
      return;
    }
    try {
      await workspace.create('payments', <String, dynamic>{
        'bookingId': booking.id,
        'amount': parsed,
        'date': todayIso(),
        'method': 'Cash',
        'reference': '',
      });
      if (context.mounted) showSnack(context, 'Payment recorded.');
    } on ApiException catch (e) {
      if (context.mounted) showSnack(context, e.message, error: true);
    }
  }
}
