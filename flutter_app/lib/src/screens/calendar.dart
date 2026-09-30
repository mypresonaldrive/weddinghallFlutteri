import 'package:flutter/material.dart';

import '../core/duration.dart' as dur;
import '../core/formatters.dart';
import '../core/models.dart';
import '../core/session.dart';
import '../core/store.dart';
import '../widgets/common.dart';
import 'booking_wizard.dart';
import 'bookings.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key, required this.session, required this.workspace});

  final SessionStore session;
  final WorkspaceStore workspace;

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  late DateTime _month;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month, 1);
  }

  List<RecordItem> _bookingsOn(String iso) {
    return widget.workspace.bookings
        .where((b) =>
            b.str('status') != 'Cancelled' && dur.occupiesDate(b.data, iso))
        .toList();
  }

  String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final today = todayIso();
    final first = _month;
    final startWeekday = (first.weekday % 7); // Monday-first → Sunday offset
    final daysInMonth = DateTime(first.year, first.month + 1, 0).day;
    final cells = <DateTime?>[
      for (var i = 0; i < startWeekday; i++) null,
      for (var d = 1; d <= daysInMonth; d++) DateTime(first.year, first.month, d),
    ];
    while (cells.length % 7 != 0) {
      cells.add(null);
    }
    final scheme = Theme.of(context).colorScheme;
    const weekdays = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];

    return PageScaffold(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Row(
                    children: [
                      IconButton(
                        tooltip: 'Previous month',
                        icon: const Icon(Icons.chevron_left),
                        onPressed: () => setState(() =>
                            _month = DateTime(_month.year, _month.month - 1, 1)),
                      ),
                      Expanded(
                        child: Center(
                          child: Text(
                            '${_month.year} · ${_monthsFull[_month.month - 1]}',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Next month',
                        icon: const Icon(Icons.chevron_right),
                        onPressed: () => setState(() =>
                            _month = DateTime(_month.year, _month.month + 1, 1)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      for (final w in weekdays)
                        Expanded(
                          child: Center(
                            child: Text(w,
                                style: Theme.of(context)
                                    .textTheme
                                    .labelSmall
                                    ?.copyWith(
                                        color: scheme.onSurfaceVariant,
                                        fontWeight: FontWeight.w700)),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  for (var week = 0; week < cells.length ~/ 7; week++)
                    Row(
                      children: [
                        for (var day = 0; day < 7; day++)
                          Expanded(
                            child: _dayCell(cells[week * 7 + day], today, scheme),
                          ),
                      ],
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text('Tap a day to view or add bookings',
              style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }

  Widget _dayCell(DateTime? day, String today, ColorScheme scheme) {
    if (day == null) return const SizedBox(height: 54);
    final iso = _iso(day);
    final bookings = _bookingsOn(iso);
    final isToday = iso == today;
    final isCurrentMonth = day.month == _month.month;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => _openDay(iso),
      child: Container(
        height: 54,
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: isToday
              ? scheme.primaryContainer
              : bookings.isNotEmpty
                  ? scheme.primary.withAlpha(18)
                  : null,
          borderRadius: BorderRadius.circular(8),
          border: isToday ? Border.all(color: scheme.primary) : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '${day.day}',
              style: TextStyle(
                fontWeight: isToday ? FontWeight.w900 : FontWeight.w600,
                color: isCurrentMonth ? null : scheme.onSurfaceVariant,
                fontSize: 13,
              ),
            ),
            if (bookings.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(top: 3),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: scheme.primary,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  bookings.length > 9 ? '9+' : '${bookings.length}',
                  style: TextStyle(
                      fontSize: 10,
                      color: scheme.onPrimary,
                      fontWeight: FontWeight.w800),
                ),
              ),
          ],
        ),
      ),
    );
  }

  static const List<String> _monthsFull = <String>[
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  Future<void> _openDay(String iso) async {
    final bookings = widget.workspace.bookings
        .where((b) => dur.occupiesDate(b.data, iso))
        .toList();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(ctx).height * 0.75,
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(formatDate(iso),
                          style: Theme.of(ctx)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800)),
                    ),
                    FilledButton.icon(
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Add booking'),
                      onPressed: () async {
                        Navigator.of(ctx).pop();
                        await _newBooking(iso);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Flexible(
                  child: bookings.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.all(20),
                          child: Text('No bookings on this day.'),
                        )
                      : ListView(
                          shrinkWrap: true,
                          children: [
                            for (final b in bookings)
                              ListTile(
                                leading: Icon(
                                  b.str('status') == 'Cancelled'
                                      ? Icons.event_busy
                                      : Icons.event,
                                  color: b.str('status') == 'Cancelled'
                                      ? const Color(0xFFB3261E)
                                      : null,
                                ),
                                title: Text(b.str('name'),
                                    style:
                                        const TextStyle(fontWeight: FontWeight.w700)),
                                subtitle: Text(
                                    '${b.str('hall')} · ${timeLabel(b.str('time'))} · ${b.str('status')}'),
                                trailing: Text(inr(b.numOf('total')),
                                    style:
                                        const TextStyle(fontWeight: FontWeight.w800)),
                                onTap: () {
                                  Navigator.of(ctx).pop();
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => BookingDetailScreen(
                                        session: widget.session,
                                        workspace: widget.workspace,
                                        bookingId: b.id,
                                      ),
                                    ),
                                  );
                                },
                              ),
                          ],
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _newBooking(String iso) async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => BookingWizard(
          session: widget.session,
          workspace: widget.workspace,
          initialDate: iso,
        ),
      ),
    );
    setState(() {});
  }
}
