import 'package:flutter/material.dart';

import '../core/formatters.dart';
import '../core/models.dart';
import '../core/session.dart';
import '../core/store.dart';
import '../widgets/common.dart';

class PaymentsScreen extends StatefulWidget {
  const PaymentsScreen({super.key, required this.session, required this.workspace});

  final SessionStore session;
  final WorkspaceStore workspace;

  @override
  State<PaymentsScreen> createState() => _PaymentsScreenState();
}

class _PaymentsScreenState extends State<PaymentsScreen> {
  String _query = '';
  String _method = 'All';
  String? _bookingFilter;

  bool get _canEdit => Perms.canManage(widget.session.user?.role, 'payments');

  String _bookingLabel(String bookingId) {
    final booking = widget.workspace.byId('bookings', bookingId);
    if (booking == null) return 'Booking';
    return '${booking.str('name')} · ${formatDate(booking.str('date'))}';
  }

  List<RecordItem> get _filtered {
    final query = _query.trim().toLowerCase();
    final items = widget.workspace.payments.where((p) {
      if (_method != 'All' && p.str('method') != _method) return false;
      if (_bookingFilter != null && p.str('bookingId') != _bookingFilter) return false;
      if (query.isEmpty) return true;
      return p.str('client').toLowerCase().contains(query) ||
          p.str('reference').toLowerCase().contains(query) ||
          _bookingLabel(p.str('bookingId')).toLowerCase().contains(query);
    }).toList()
      ..sort((a, b) => b.str('date').compareTo(a.str('date')));
    return items;
  }

  @override
  Widget build(BuildContext context) {
    final payments = _filtered;
    final total = payments.fold<double>(0, (s, p) => s + p.numOf('amount').toDouble());
    return PageScaffold(
      floatingActionButton: _canEdit
          ? FloatingActionButton.extended(
              onPressed: () => _recordPayment(null),
              icon: const Icon(Icons.add),
              label: const Text('Record payment'),
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 240,
                child: TextField(
                  decoration: inputDecoration('Search payments', prefixIcon: Icons.search),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
              SizedBox(
                width: 170,
                child: DropdownButtonFormField<String>(
                  initialValue: _method,
                  decoration: inputDecoration('Method'),
                  items: [
                    const DropdownMenuItem(value: 'All', child: Text('All methods')),
                    for (final m in const <String>[
                      'Cash',
                      'UPI',
                      'Bank transfer',
                      'Cheque',
                      'Card',
                      'Other'
                    ])
                      DropdownMenuItem(value: m, child: Text(m)),
                  ],
                  onChanged: (v) => setState(() => _method = v ?? 'All'),
                ),
              ),
              if (_bookingFilter != null)
                ActionChip(
                  avatar: const Icon(Icons.filter_alt_off, size: 16),
                  label: Text('Clear booking filter',
                      style: const TextStyle(fontSize: 12.5)),
                  onPressed: () => setState(() => _bookingFilter = null),
                ),
              Text('Shown: ${inr(total)}',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 12),
          if (widget.workspace.loading && payments.isEmpty)
            const LoadingCenter()
          else if (payments.isEmpty)
            const EmptyState(
              icon: Icons.payments_outlined,
              title: 'No payments found',
              message: 'Record payments against bookings to track balances.',
            )
          else
            ResponsiveRecords(
              widthForTable: 980,
              headers: const ['Date', 'Booking / client', 'Method', 'Reference', 'Amount', 'Actions'],
              rows: [
                for (final payment in payments) _tableRow(payment),
              ],
              cardBuilder: (i) => _paymentCard(payments[i]),
            ),
        ],
      ),
    );
  }

  List<Widget> _tableRow(RecordItem payment) {
    return [
      Text(formatDate(payment.str('date')), style: const TextStyle(fontWeight: FontWeight.w600)),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(payment.str('client'), style: const TextStyle(fontWeight: FontWeight.w700)),
          Text(_bookingLabel(payment.str('bookingId')),
              style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
      Text(payment.str('method')),
      Text(payment.str('reference')),
      Text(inr(payment.numOf('amount')),
          style: const TextStyle(fontWeight: FontWeight.w800)),
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_canEdit) ...[
            IconButton(
              tooltip: 'Edit',
              icon: const Icon(Icons.edit_outlined, size: 20),
              onPressed: () => _recordPayment(payment),
            ),
            IconButton(
              tooltip: 'Delete',
              icon: const Icon(Icons.delete_outline, size: 20),
              onPressed: () => _deletePayment(payment),
            ),
          ] else
            const Text('—'),
        ],
      ),
    ];
  }

  Widget _paymentCard(RecordItem payment) {
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
                  child: Text(inr(payment.numOf('amount')),
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                ),
                StatusChip(label: payment.str('method'), tone: 'blue'),
              ],
            ),
            Text('${payment.str('client')} · ${formatDate(payment.str('date'))}'),
            Text(_bookingLabel(payment.str('bookingId')),
                style: Theme.of(context).textTheme.bodySmall),
            if (payment.str('reference').isNotEmpty)
              Text('Ref ${payment.str('reference')}',
                  style: Theme.of(context).textTheme.bodySmall),
            if (_canEdit)
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                      onPressed: () => _recordPayment(payment),
                      child: const Text('Edit')),
                  TextButton(
                      onPressed: () => _deletePayment(payment),
                      child: const Text('Delete',
                          style: TextStyle(color: Color(0xFFB3261E)))),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _deletePayment(RecordItem payment) async {
    final ok = await confirmDialog(
      context,
      title: 'Delete payment',
      message: 'Delete the ${inr(payment.numOf('amount'))} payment recorded on '
          '${formatDate(payment.str('date'))}?',
      confirmLabel: 'Delete',
    );
    if (!ok || !mounted) return;
    try {
      await widget.workspace.remove('payments', payment.id);
      if (mounted) showSnack(context, 'Payment deleted.');
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    }
  }

  Future<void> _recordPayment(RecordItem? existing) async {
    final bookings = widget.workspace.bookings
        .where((b) => b.str('status') != 'Cancelled')
        .toList();
    if (bookings.isEmpty && existing == null) {
      showSnack(context, 'Create a booking before recording payments.', error: true);
      return;
    }
    String bookingId = existing?.str('bookingId') ??
        (bookings.isEmpty ? '' : bookings.first.id);
    final amount = TextEditingController(
        text: existing == null ? '' : '${existing.numOf('amount')}');
    final date = ValueNotifier<String>(existing?.str('date') ?? todayIso());
    final method =
        ValueNotifier<String>(existing?.str('method', 'Cash') ?? 'Cash');
    final reference = TextEditingController(text: existing?.str('reference') ?? '');
    final formKey = GlobalKey<FormState>();
    var saving = false;

    double remainingFor(String id) {
      final booking = widget.workspace.byId('bookings', id);
      if (booking == null) return 0;
      final paid = existing != null && existing.str('bookingId') == id
          ? paidFor(widget.workspace.payments, id) - existing.numOf('amount').toDouble()
          : paidFor(widget.workspace.payments, id);
      return booking.numOf('total').toDouble() - paid;
    }

    final saved = await showAppDialog<bool>(context, builder: (ctx) {
      return StatefulBuilder(builder: (setLocal) {
        final remaining = remainingFor(bookingId);
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(existing == null ? 'Record payment' : 'Edit payment',
                    style: Theme.of(ctx)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 16),
                StatefulBuilder(builder: (setBooking) {
                  final items = <DropdownMenuItem<String>>[
                    for (final b in bookings)
                      DropdownMenuItem(
                        value: b.id,
                        child: Text(
                            '${b.str('name')} · ${formatDate(b.str('date'))} · bal ${inr(b.numOf('total') - paidFor(widget.workspace.payments, b.id))}',
                            overflow: TextOverflow.ellipsis),
                      ),
                  ];
                  if (bookingId.isNotEmpty && !items.any((i) => i.value == bookingId)) {
                    final extra = widget.workspace.byId('bookings', bookingId);
                    if (extra != null) {
                      items.add(DropdownMenuItem(
                        value: bookingId,
                        child: Text(
                            '${extra.str('name')} · ${formatDate(extra.str('date'))}',
                            overflow: TextOverflow.ellipsis),
                      ));
                    }
                  }
                  return DropdownButtonFormField<String>(
                    initialValue: bookingId.isEmpty ? null : bookingId,
                    decoration: inputDecoration('Booking'),
                    items: items,
                    onChanged: (v) {
                      setBooking(() => bookingId = v ?? bookingId);
                      setLocal(() {});
                    },
                    validator: (v) =>
                        (v ?? '').isEmpty ? 'Choose a booking.' : null,
                  );
                }),
                const SizedBox(height: 12),
                TextFormField(
                  controller: amount,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: inputDecoration(
                      'Amount (₹) — remaining ${inr(remaining)}'),
                  validator: (v) => numberText(v, 'Amount', min: 0.01),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: ValueListenableBuilder<String>(
                        valueListenable: date,
                        builder: (_, value, __) => InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: () async {
                            final picked = await showDatePicker(
                              context: ctx,
                              initialDate: DateTime.tryParse(value) ?? DateTime.now(),
                              firstDate: DateTime(2015),
                              lastDate: DateTime(2100),
                            );
                            if (picked != null) {
                              date.value =
                                  '${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
                            }
                          },
                          child: InputDecorator(
                            decoration: inputDecoration('Payment date',
                                prefixIcon: Icons.calendar_today_outlined),
                            child: Text(formatDate(value)),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ValueListenableBuilder<String>(
                        valueListenable: method,
                        builder: (_, value, __) => DropdownButtonFormField<String>(
                          initialValue: value,
                          decoration: inputDecoration('Method'),
                          items: [
                            for (final m in const <String>[
                              'Cash',
                              'UPI',
                              'Bank transfer',
                              'Cheque',
                              'Card',
                              'Other'
                            ])
                              DropdownMenuItem(value: m, child: Text(m)),
                          ],
                          onChanged: (v) => method.value = v ?? 'Cash',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: reference,
                  decoration: inputDecoration('Reference (optional)',
                      hint: 'UPI txn id, cheque number…'),
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
                                  'bookingId': bookingId,
                                  'amount': num.tryParse(amount.text.trim()) ?? 0,
                                  'date': date.value,
                                  'method': method.value,
                                  'reference': reference.text.trim(),
                                };
                                if (existing == null) {
                                  await widget.workspace.create('payments', body);
                                } else {
                                  await widget.workspace
                                      .update('payments', existing.id, body);
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
      showSnack(context, existing == null ? 'Payment recorded.' : 'Payment updated.');
    }
  }
}
