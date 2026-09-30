import 'package:flutter/material.dart';

import '../core/duration.dart';

import '../core/formatters.dart';
import '../core/models.dart';
import '../core/session.dart';
import '../core/store.dart';
import '../widgets/common.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key, required this.session, required this.workspace});

  final SessionStore session;
  final WorkspaceStore workspace;

  @override
  Widget build(BuildContext context) {
    final bookings = workspace.bookings;
    final payments = workspace.payments;
    final clients = workspace.clients;
    final halls = workspace.halls;
    final today = todayIso();

    final activeBookings =
        bookings.where((b) => b.str('status') != 'Cancelled').toList();
    final upcoming = activeBookings
        .where((b) => b.str('date').compareTo(today) >= 0 && b.str('status') != 'Completed')
        .toList()
      ..sort((a, b) => a.str('date').compareTo(b.str('date')));
    final pending = bookings.where((b) => b.str('status') == 'Pending').toList();
    final thisMonth = today.substring(0, 7);
    final monthRevenue = payments
        .where((p) => p.str('date').startsWith(thisMonth))
        .fold<double>(0, (sum, p) => sum + p.numOf('amount').toDouble());
    final outstanding = activeBookings.fold<double>(
        0, (sum, b) => sum + (b.numOf('total') - paidFor(payments, b.id)).toDouble());
    final activeClients =
        clients.where((c) => c.str('status') == 'Active').length;

    if (workspace.loading && bookings.isEmpty) {
      return const LoadingCenter(label: 'Loading dashboard…');
    }
    if (workspace.error != null && bookings.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: ErrorBanner(
            message: workspace.error!, onRetry: () => workspace.load()),
      );
    }

    return PageScaffold(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (session.user?.entitlementActive == false && session.config.isSaas) ...[
            const ErrorBanner(
                message: 'Subscription inactive — renew from Billing to resume changes.'),
            const SizedBox(height: 12),
          ],
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              SizedBox(
                width: 240,
                child: StatTile(
                  label: 'Upcoming bookings',
                  value: '${upcoming.length}',
                  icon: Icons.event,
                  caption: upcoming.isEmpty
                      ? 'Nothing scheduled'
                      : 'Next: ${formatDate(upcoming.first.str('date'))}',
                ),
              ),
              SizedBox(
                width: 240,
                child: StatTile(
                  label: 'Collected this month',
                  value: inr(monthRevenue),
                  icon: Icons.trending_up,
                  tone: const Color(0xFF1B7F4C),
                  caption: '${payments.length} payments recorded',
                ),
              ),
              SizedBox(
                width: 240,
                child: StatTile(
                  label: 'Outstanding balance',
                  value: inr(outstanding),
                  icon: Icons.account_balance_wallet_outlined,
                  tone: const Color(0xFF9A6700),
                  caption: 'Across ${activeBookings.length} bookings',
                ),
              ),
              SizedBox(
                width: 240,
                child: StatTile(
                  label: 'Pending requests',
                  value: '${pending.length}',
                  icon: Icons.hourglass_bottom,
                  tone: const Color(0xFF6A4BBC),
                  caption: '${activeClients} active clients · ${halls.length} halls',
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 900;
              final upcomingCard = _UpcomingCard(bookings: upcoming, workspace: workspace);
              final recentCard = _RecentPaymentsCard(payments: payments);
              if (wide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: upcomingCard),
                    const SizedBox(width: 14),
                    Expanded(child: recentCard),
                  ],
                );
              }
              return Column(children: [upcomingCard, const SizedBox(height: 14), recentCard]);
            },
          ),
          const SizedBox(height: 14),
          _HallOccupancyCard(workspace: workspace),
        ],
      ),
    );
  }
}

class _UpcomingCard extends StatelessWidget {
  const _UpcomingCard({required this.bookings, required this.workspace});

  final List<RecordItem> bookings;
  final WorkspaceStore workspace;

  @override
  Widget build(BuildContext context) {
    final top = bookings.take(8).toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Upcoming events',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            if (top.isEmpty)
              const Padding(
                padding: EdgeInsets.all(14),
                child: Text('No upcoming events. Create a booking to see it here.'),
              )
            else
              for (final b in top)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: Container(
                    width: 4,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  title: Text(b.str('name'),
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(
                      '${formatDate(b.str('date'))} · ${b.str('hall')} · ${b.str('guests')} guests'),
                  trailing: StatusChip(
                    label: b.str('status'),
                    tone: statusColorName(b.str('status')),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

class _RecentPaymentsCard extends StatelessWidget {
  const _RecentPaymentsCard({required this.payments});

  final List<RecordItem> payments;

  @override
  Widget build(BuildContext context) {
    final recent = List<RecordItem>.from(payments)
      ..sort((a, b) => b.str('date').compareTo(a.str('date')));
    final top = recent.take(8).toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Recent payments',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            if (top.isEmpty)
              const Padding(
                padding: EdgeInsets.all(14),
                child: Text('No payments recorded yet.'),
              )
            else
              for (final p in top)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: CircleAvatar(
                    radius: 16,
                    backgroundColor:
                        Theme.of(context).colorScheme.primaryContainer,
                    child: Icon(Icons.payments_outlined,
                        size: 16, color: Theme.of(context).colorScheme.onPrimaryContainer),
                  ),
                  title: Text(inr(p.numOf('amount')),
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: Text(
                      '${p.str('client')} · ${formatDate(p.str('date'))} · ${p.str('method')}'),
                ),
          ],
        ),
      ),
    );
  }
}

class _HallOccupancyCard extends StatelessWidget {
  const _HallOccupancyCard({required this.workspace});

  final WorkspaceStore workspace;

  @override
  Widget build(BuildContext context) {
    final today = todayIso();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Halls today',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final hall in workspace.halls)
                  Builder(builder: (context) {
                    final bookingsToday = workspace.bookings.where((b) =>
                        b.hallIdOr(hall.id) &&
                        b.str('status') != 'Cancelled' &&
                        occupiesDate(b.data, today));
                    final occupied = bookingsToday.isNotEmpty;
                    return Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: occupied
                            ? const Color(0xFFFFF4E5)
                            : const Color(0xFFE7F6EE),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(hall.str('name'),
                              style: const TextStyle(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 2),
                          Text(
                            occupied
                                ? bookingsToday.first.str('name')
                                : 'Open · ${hall.str('status')}',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: occupied
                                  ? const Color(0xFF7A4D00)
                                  : const Color(0xFF145C37),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

extension on RecordItem {
  bool hallIdOr(String hallId) => str('hallId') == hallId;
}
