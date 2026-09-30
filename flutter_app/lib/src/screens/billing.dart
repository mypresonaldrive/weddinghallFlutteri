import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/formatters.dart';
import '../core/session.dart';
import '../core/store.dart';
import '../widgets/common.dart';

class BillingScreen extends StatefulWidget {
  const BillingScreen({super.key, required this.session, required this.workspace});

  final SessionStore session;
  final WorkspaceStore workspace;

  @override
  State<BillingScreen> createState() => _BillingScreenState();
}

class _BillingScreenState extends State<BillingScreen> {
  Map<String, dynamic>? _billing;
  String? _error;
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _billing = await widget.workspace.billing();
    } on ApiException catch (e) {
      _error = e.message;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _refresh() async {
    setState(() => _busy = true);
    try {
      await widget.session.api.post('/api/billing/refresh');
      await _load();
      if (mounted) showSnack(context, 'Subscription status refreshed.');
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancel() async {
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel renewal'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
                'Access continues until the end of the paid period. Type the confirmation phrase below.'),
            const SizedBox(height: 10),
            TextField(
              controller: controller,
              decoration: const InputDecoration(labelText: 'Type CANCEL RENEWAL'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Keep subscription')),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(
                  controller.text.trim() == 'CANCEL RENEWAL'),
              child: const Text('Cancel renewal')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.session.api
          .post('/api/billing/cancel', {'confirm': 'CANCEL RENEWAL'});
      await _load();
      if (mounted) showSnack(context, 'Renewal cancellation requested.');
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _billing == null) return const LoadingCenter();
    if (_error != null && _billing == null) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: ErrorBanner(message: _error!, onRetry: _load),
      );
    }
    final data = _billing ?? <String, dynamic>{};
    final organization = data['organization'] is Map
        ? Map<String, dynamic>.from(data['organization'] as Map)
        : <String, dynamic>{};
    final subscription = data['subscription'] is Map
        ? Map<String, dynamic>.from(data['subscription'] as Map)
        : <String, dynamic>{};
    final entitlement = data['entitlement'] is Map
        ? Map<String, dynamic>.from(data['entitlement'] as Map)
        : <String, dynamic>{};
    final usage = data['usage'] is Map
        ? Map<String, dynamic>.from(data['usage'] as Map)
        : <String, dynamic>{};
    final payments = (data['payments'] as List<dynamic>? ?? <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .toList();
    final billingEnabled = data['billingEnabled'] == true;
    final planSnapshot = subscription['plan_snapshot'] is Map
        ? Map<String, dynamic>.from(subscription['plan_snapshot'] as Map)
        : <String, dynamic>{};
    final active = entitlement['active'] == true;
    String dateOnly(dynamic value) =>
        value is String && value.length >= 10 ? value.substring(0, 10) : '';

    return PageScaffold(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!active) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF4E5),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  (entitlement['reason'] ?? 'Subscription inactive').toString(),
                  style: const TextStyle(
                      color: Color(0xFF7A4D00), fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(height: 12),
            ],
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                SizedBox(
                  width: 240,
                  child: StatTile(
                    label: 'Plan',
                    value: (planSnapshot['name'] ?? 'No plan').toString(),
                    icon: Icons.workspace_premium_outlined,
                    caption: '${subscription['interval'] ?? ''} · ${(subscription['status'] ?? '').toString()}',
                  ),
                ),
                SizedBox(
                  width: 240,
                  child: StatTile(
                    label: 'Paid through',
                    value: dateOnly(subscription['paid_through']).isEmpty
                        ? (subscription['trial_until'] != null ? 'Trial' : '—')
                        : formatDate(dateOnly(subscription['paid_through'])),
                    icon: Icons.event_available_outlined,
                    tone: const Color(0xFF1B7F4C),
                    caption: dateOnly(subscription['trial_until']).isEmpty
                        ? null
                        : 'Trial ends ${formatDate(dateOnly(subscription['trial_until']))}',
                  ),
                ),
                SizedBox(
                  width: 240,
                  child: StatTile(
                    label: 'Halls used',
                    value: '${usage['halls'] ?? 0} / ${planSnapshot['max_halls'] ?? '—'}',
                    icon: Icons.warehouse_outlined,
                    tone: const Color(0xFF6A4BBC),
                    caption: 'Staff ${usage['staff'] ?? 0} / ${planSnapshot['max_staff'] ?? '—'}',
                  ),
                ),
                SizedBox(
                  width: 240,
                  child: StatTile(
                    label: 'Renewal',
                    value: subscription['cancel_at_period_end'] == true
                        ? 'Cancelling'
                        : (subscription['provider_subscription_id'] != null
                            ? 'Active mandate'
                            : 'Not started'),
                    icon: Icons.autorenew,
                    tone: const Color(0xFF9A6700),
                    caption: billingEnabled ? 'Billing configured' : 'Billing not configured',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Subscription controls',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    Text(
                      subscription['provider_subscription_id'] == null
                          ? 'Start checkout from the web billing page (Razorpay checkout needs a browser). The Flutter app shows status once the mandate exists.'
                          : 'Status follows Razorpay. Webhooks update entitlements automatically.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          icon: const Icon(Icons.refresh, size: 18),
                          label: const Text('Refresh status'),
                          onPressed: _busy ? null : _refresh,
                        ),
                        if (subscription['provider_subscription_id'] != null &&
                            subscription['cancel_at_period_end'] != true)
                          OutlinedButton.icon(
                            icon: const Icon(Icons.cancel_outlined, size: 18),
                            label: const Text('Cancel renewal'),
                            onPressed: _busy ? null : _cancel,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Recent billing payments',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 6),
                    if (payments.isEmpty)
                      const Text('No subscription payments captured yet.')
                    else
                      for (final p in payments.take(20))
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          leading: const Icon(Icons.receipt_long_outlined),
                          title: Text(
                              '${inr(((p['amount_paise'] as num?) ?? 0) / 100)} · ${p['currency'] ?? 'INR'}',
                              style: const TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: Text(
                              'Captured ${formatDate(dateOnly(p['captured_at']))} · ${p['provider_payment_id'] ?? ''}'),
                        ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
