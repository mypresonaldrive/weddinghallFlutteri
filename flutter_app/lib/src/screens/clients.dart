import 'package:flutter/material.dart';

import '../core/api.dart';

import '../core/formatters.dart';
import '../core/models.dart';
import '../core/session.dart';
import '../core/store.dart';
import '../widgets/common.dart';

class ClientsScreen extends StatefulWidget {
  const ClientsScreen({super.key, required this.session, required this.workspace});

  final SessionStore session;
  final WorkspaceStore workspace;

  @override
  State<ClientsScreen> createState() => _ClientsScreenState();
}

class _ClientsScreenState extends State<ClientsScreen> {
  String _query = '';
  String _status = 'All';

  bool get _canEdit => Perms.canManage(widget.session.user?.role, 'clients');
  bool get _canProvision => widget.session.user?.isOwner == true;

  List<RecordItem> get _filtered {
    final query = _query.trim().toLowerCase();
    return widget.workspace.clients.where((c) {
      if (_status != 'All' && c.str('status') != _status) return false;
      if (query.isEmpty) return true;
      return c.str('name').toLowerCase().contains(query) ||
          c.str('email').toLowerCase().contains(query) ||
          c.str('phone').toLowerCase().contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final clients = _filtered;
    return PageScaffold(
      floatingActionButton: _canEdit
          ? FloatingActionButton.extended(
              onPressed: () => _editClient(null),
              icon: const Icon(Icons.add),
              label: const Text('Add client'),
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
                width: 260,
                child: TextField(
                  decoration: inputDecoration('Search clients', prefixIcon: Icons.search),
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
          if (widget.workspace.loading && clients.isEmpty)
            const LoadingCenter()
          else if (clients.isEmpty)
            const EmptyState(
              icon: Icons.people_outline,
              title: 'No clients found',
              message: 'Add clients to link them with bookings and payments.',
            )
          else
            ResponsiveRecords(
              widthForTable: 900,
              headers: const ['Client', 'Email', 'Phone', 'Status', 'Actions'],
              rows: [
                for (final client in clients) _tableRow(client),
              ],
              cardBuilder: (i) => _clientCard(clients[i]),
            ),
        ],
      ),
    );
  }

  List<Widget> _tableRow(RecordItem client) {
    return [
      Text(client.str('name'), style: const TextStyle(fontWeight: FontWeight.w700)),
      Text(client.str('email')),
      Text(client.str('phone')),
      StatusChip(
          label: client.str('status'), tone: statusColorName(client.str('status'))),
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_canEdit) ...[
            IconButton(
              tooltip: 'Edit',
              icon: const Icon(Icons.edit_outlined, size: 20),
              onPressed: () => _editClient(client),
            ),
            IconButton(
              tooltip: 'Delete',
              icon: const Icon(Icons.delete_outline, size: 20),
              onPressed: () => _deleteClient(client),
            ),
          ] else
            const Text('—'),
        ],
      ),
    ];
  }

  Widget _clientCard(RecordItem client) {
    final bookingCount =
        widget.workspace.bookings.where((b) => b.str('clientId') == client.id).length;
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
                  child: Text(client.str('name'),
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                ),
                StatusChip(
                    label: client.str('status'),
                    tone: statusColorName(client.str('status'))),
              ],
            ),
            const SizedBox(height: 4),
            Text(client.str('email')),
            Text('${client.str('phone')} · $bookingCount bookings',
                style: Theme.of(context).textTheme.bodySmall),
            if (_canEdit)
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                      onPressed: () => _editClient(client), child: const Text('Edit')),
                  TextButton(
                      onPressed: () => _deleteClient(client),
                      child: const Text('Delete',
                          style: TextStyle(color: Color(0xFFB3261E)))),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteClient(RecordItem client) async {
    final ok = await confirmDialog(
      context,
      title: 'Delete client',
      message:
          'Delete "${client.str('name')}"? Clients with bookings must have those bookings removed first.',
      confirmLabel: 'Delete',
    );
    if (!ok || !mounted) return;
    try {
      await widget.workspace.remove('clients', client.id);
      if (mounted) showSnack(context, 'Client deleted.');
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    }
  }

  Future<void> _editClient(RecordItem? existing) async {
    final name = TextEditingController(text: existing?.str('name') ?? '');
    final email = TextEditingController(text: existing?.str('email') ?? '');
    final phone = TextEditingController(text: existing?.str('phone') ?? '');
    final notes = TextEditingController(text: existing?.str('notes') ?? '');
    final password = TextEditingController();
    final status =
        ValueNotifier<String>(existing?.str('status', 'Active') ?? 'Active');
    final formKey = GlobalKey<FormState>();
    var saving = false;

    final saved = await showAppDialog<bool>(context, builder: (ctx) {
      return StatefulBuilder(builder: (_, setLocal) {
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(existing == null ? 'Add client' : 'Edit client',
                    style: Theme.of(ctx)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 16),
                TextFormField(
                  controller: name,
                  decoration: inputDecoration('Full name'),
                  validator: (v) => requiredText(v, 'Name', max: 200),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: inputDecoration('Email'),
                  validator: emailText,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: phone,
                        keyboardType: TextInputType.phone,
                        decoration: inputDecoration('Phone'),
                        validator: (v) => requiredText(v, 'Phone', max: 200),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ValueListenableBuilder<String>(
                        valueListenable: status,
                        builder: (_, value, __) => DropdownButtonFormField<String>(
                          initialValue: value,
                          decoration: inputDecoration('Status'),
                          items: const [
                            DropdownMenuItem(value: 'Active', child: Text('Active')),
                            DropdownMenuItem(value: 'Inactive', child: Text('Inactive')),
                          ],
                          onChanged: (v) => status.value = v ?? 'Active',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: notes,
                  maxLines: 2,
                  decoration: inputDecoration('Notes'),
                ),
                if (existing == null && _canProvision) ...[
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: password,
                    obscureText: true,
                    decoration: inputDecoration(
                      widget.session.config.isSaas ? 'Initial password (not available)' : 'Workspace password (optional)',
                      hint: widget.session.config.isSaas
                          ? 'Use email invitations from the Team screen instead'
                          : 'At least 8 characters to create a sign-in',
                    ),
                    enabled: !widget.session.config.isSaas,
                    validator: (v) {
                      final text = v ?? '';
                      if (text.isEmpty) return null;
                      if (text.length < 8) return 'Use at least 8 characters.';
                      return null;
                    },
                  ),
                ],
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
                                  'email': email.text.trim(),
                                  'phone': phone.text.trim(),
                                  'notes': notes.text.trim(),
                                  'status': status.value,
                                };
                                if (password.text.isNotEmpty) {
                                  body['loginPassword'] = password.text;
                                }
                                if (existing == null) {
                                  await widget.workspace.create('clients', body);
                                } else {
                                  await widget.workspace
                                      .update('clients', existing.id, body);
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
      showSnack(context, existing == null ? 'Client added.' : 'Client updated.');
    }
  }
}
