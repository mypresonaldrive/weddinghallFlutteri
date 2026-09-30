import 'dart:io';

import 'package:flutter/material.dart';

import '../core/constants.dart';

import '../core/csv.dart';
import '../core/formatters.dart';
import '../core/paths.dart';
import '../core/models.dart';
import '../core/store.dart';
import '../widgets/common.dart';

class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key, required this.workspace});

  final WorkspaceStore workspace;

  @override
  Widget build(BuildContext context) {
    final payments = workspace.payments;
    final bookings = workspace.bookings;
    final totalPaid = payments.fold<double>(0, (s, p) => s + p.numOf('amount').toDouble());
    final activeBookings =
        bookings.where((b) => b.str('status') != 'Cancelled').toList();
    final outstanding = activeBookings.fold<double>(
        0, (s, b) => s + (b.numOf('total') - paidFor(payments, b.id)).toDouble());

    // Last 6 months revenue.
    final now = DateTime.now();
    final months = <String>[];
    for (var i = 5; i >= 0; i--) {
      final d = DateTime(now.year, now.month - i, 1);
      months.add(monthIso(d.year, d.month));
    }
    final monthly = <String, double>{
      for (final m in months)
        m: payments
            .where((p) => p.str('date').startsWith(m))
            .fold<double>(0, (s, p) => s + p.numOf('amount').toDouble()),
    };
    final maxMonth = monthly.values.fold<double>(0, (a, b) => a > b ? a : b);

    final byHall = <String, double>{};
    for (final b in activeBookings) {
      final hall = b.str('hall');
      byHall[hall] = (byHall[hall] ?? 0) + b.numOf('total').toDouble();
    }
    final hallEntries = byHall.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final statusCounts = <String, int>{
      for (final s in bookingStatuses) s: bookings.where((b) => b.str('status') == s).length,
    };

    return PageScaffold(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              SizedBox(
                width: 220,
                child: StatTile(
                  label: 'Total collected',
                  value: inr(totalPaid),
                  icon: Icons.savings_outlined,
                  tone: const Color(0xFF1B7F4C),
                ),
              ),
              SizedBox(
                width: 220,
                child: StatTile(
                  label: 'Outstanding',
                  value: inr(outstanding),
                  icon: Icons.pending_actions_outlined,
                  tone: const Color(0xFF9A6700),
                ),
              ),
              SizedBox(
                width: 220,
                child: StatTile(
                  label: 'Bookings',
                  value: '${bookings.length}',
                  icon: Icons.event_note_outlined,
                  caption: '${statusCounts['Confirmed'] ?? 0} confirmed',
                ),
              ),
              SizedBox(
                width: 220,
                child: StatTile(
                  label: 'Clients',
                  value: '${workspace.clients.length}',
                  icon: Icons.people_outline,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          LayoutBuilder(builder: (context, constraints) {
            final wide = constraints.maxWidth >= 900;
            final revenueCard = _card(
              context,
              'Revenue — last 6 months',
              Column(
                children: [
                  for (final entry in monthly.entries)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Row(
                        children: [
                          SizedBox(
                              width: 70,
                              child: Text(formatDateShort('${entry.key}-01'),
                                  style: Theme.of(context).textTheme.bodySmall)),
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: maxMonth == 0 ? 0 : entry.value / maxMonth,
                                minHeight: 10,
                                backgroundColor: Theme.of(context)
                                    .colorScheme
                                    .surfaceContainerHighest,
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 110,
                            child: Text(inr(entry.value),
                                textAlign: TextAlign.right,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700, fontSize: 13)),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            );
            final hallsCard = _card(
              context,
              'Booking value by hall',
              Column(
                children: [
                  for (final entry in hallEntries.take(8))
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(entry.key,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      trailing: Text(inr(entry.value),
                          style: const TextStyle(fontWeight: FontWeight.w800)),
                    ),
                  if (hallEntries.isEmpty)
                    const Text('No bookings to summarise yet.'),
                ],
              ),
            );
            if (wide) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: revenueCard),
                  const SizedBox(width: 14),
                  Expanded(child: hallsCard),
                ],
              );
            }
            return Column(children: [revenueCard, const SizedBox(height: 14), hallsCard]);
          }),
          const SizedBox(height: 14),
          _card(
            context,
            'Export CSV',
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Files are written to the app data folder on this device.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      icon: const Icon(Icons.event_note_outlined, size: 18),
                      label: const Text('Bookings'),
                      onPressed: () => _exportBookings(context),
                    ),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.payments_outlined, size: 18),
                      label: const Text('Payments'),
                      onPressed: () => _exportPayments(context),
                    ),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.people_outline, size: 18),
                      label: const Text('Clients'),
                      onPressed: () => _exportClients(context),
                    ),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.warehouse_outlined, size: 18),
                      label: const Text('Halls'),
                      onPressed: () => _exportHalls(context),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _card(BuildContext context, String title, Widget child) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }

  Future<void> _writeCsv(BuildContext context, String name, List<List<String>> rows) async {
    try {
      final dir = await _exportDir();
      final stamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .split('.')
          .first;
      final file = File('${dir.path}${Platform.pathSeparator}$name-$stamp.csv');
      await file.writeAsString(csvEncode(rows), flush: true);
      if (context.mounted) {
        showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text('$name.csv exported'),
            content: SelectableText(file.path),
            actions: [
              TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Close')),
            ],
          ),
        );
      }
    } catch (e) {
      if (context.mounted) showSnack(context, 'Export failed: $e', error: true);
    }
  }

  Future<Directory> _exportDir() async {
    // Reuse the state directory helper.
    final base = await _stateDir();
    final dir = Directory('${base.path}${Platform.pathSeparator}exports');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<Directory> _stateDir() => appStateDir();

  void _exportBookings(BuildContext context) {
    final rows = <List<String>>[
      ['ID', 'Event', 'Client', 'Hall', 'Date', 'Duration mode', 'Guests', 'Type', 'Status', 'Total', 'Paid', 'Balance'],
      for (final b in workspace.bookings)
        [
          b.id,
          b.str('name'),
          b.str('client'),
          b.str('hall'),
          b.str('date'),
          b.str('durationMode', 'full'),
          '${b.numOf('guests').toInt()}',
          b.str('type'),
          b.str('status'),
          '${b.numOf('total')}',
          '${paidFor(workspace.payments, b.id)}',
          '${balanceFor(b, workspace.payments)}',
        ],
    ];
    _writeCsv(context, 'bookings', rows);
  }

  void _exportPayments(BuildContext context) {
    final rows = <List<String>>[
      ['ID', 'Date', 'Booking', 'Client', 'Amount', 'Method', 'Reference', 'Status'],
      for (final p in workspace.payments)
        [
          p.id,
          p.str('date'),
          p.str('bookingId'),
          p.str('client'),
          '${p.numOf('amount')}',
          p.str('method'),
          p.str('reference'),
          p.str('status'),
        ],
    ];
    _writeCsv(context, 'payments', rows);
  }

  void _exportClients(BuildContext context) {
    final rows = <List<String>>[
      ['ID', 'Name', 'Email', 'Phone', 'Status', 'Notes'],
      for (final c in workspace.clients)
        [c.id, c.str('name'), c.str('email'), c.str('phone'), c.str('status'), c.str('notes')],
    ];
    _writeCsv(context, 'clients', rows);
  }

  void _exportHalls(BuildContext context) {
    final rows = <List<String>>[
      ['ID', 'Name', 'Type', 'Capacity', 'Base price', 'Status'],
      for (final h in workspace.halls)
        [
          h.id,
          h.str('name'),
          h.str('type'),
          '${h.numOf('capacity').toInt()}',
          '${h.numOf('price')}',
          h.str('status'),
        ],
    ];
    _writeCsv(context, 'halls', rows);
  }
}
