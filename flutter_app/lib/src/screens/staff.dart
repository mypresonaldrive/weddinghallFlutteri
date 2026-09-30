import 'package:flutter/material.dart';

import '../core/formatters.dart';
import '../core/models.dart';
import '../core/session.dart';
import '../core/store.dart';
import '../widgets/common.dart';

class StaffScreen extends StatefulWidget {
  const StaffScreen({super.key, required this.session, required this.workspace});

  final SessionStore session;
  final WorkspaceStore workspace;

  @override
  State<StaffScreen> createState() => _StaffScreenState();
}

class _StaffScreenState extends State<StaffScreen> {
  String _query = '';

  bool get _isSaas => widget.session.config.isSaas;

  List<RecordItem> get _filtered {
    final query = _query.trim().toLowerCase();
    return widget.workspace.staff.where((s) {
      if (query.isEmpty) return true;
      return s.str('name').toLowerCase().contains(query) ||
          s.str('position').toLowerCase().contains(query) ||
          s.str('email').toLowerCase().contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final members = _filtered;
    return PageScaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _editMember(null),
        icon: const Icon(Icons.person_add_alt),
        label: const Text('Add member'),
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
                width: 280,
                child: TextField(
                  decoration: inputDecoration('Search team', prefixIcon: Icons.search),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
              if (_isSaas)
                Text(
                  'Email invitations are sent from each member row.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (widget.workspace.loading && members.isEmpty)
            const LoadingCenter()
          else if (members.isEmpty)
            const EmptyState(
              icon: Icons.groups_2_outlined,
              title: 'No team members',
              message: 'Add staff accounts to share workspace management.',
            )
          else
            ResponsiveRecords(
              widthForTable: 940,
              headers: const ['Member', 'Position', 'Email', 'Phone', 'Status', 'Actions'],
              rows: [
                for (final member in members) _tableRow(member),
              ],
              cardBuilder: (i) => _memberCard(members[i]),
            ),
        ],
      ),
    );
  }

  List<Widget> _tableRow(RecordItem member) {
    return [
      Text(member.str('name'), style: const TextStyle(fontWeight: FontWeight.w700)),
      Text(member.str('position')),
      Text(member.str('email')),
      Text(member.str('phone')),
      StatusChip(
          label: member.str('status'), tone: statusColorName(member.str('status'))),
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_isSaas)
            IconButton(
              tooltip: 'Send invitation email',
              icon: const Icon(Icons.mail_outline, size: 20),
              onPressed: () => _invite(member),
            ),
          IconButton(
            tooltip: 'Edit',
            icon: const Icon(Icons.edit_outlined, size: 20),
            onPressed: () => _editMember(member),
          ),
          IconButton(
            tooltip: 'Delete',
            icon: const Icon(Icons.delete_outline, size: 20),
            onPressed: () => _deleteMember(member),
          ),
        ],
      ),
    ];
  }

  Widget _memberCard(RecordItem member) {
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
                  child: Text(member.str('name'),
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                ),
                StatusChip(
                    label: member.str('status'),
                    tone: statusColorName(member.str('status'))),
              ],
            ),
            Text('${member.str('position')} · ${member.str('email')}'),
            Text(member.str('phone'), style: Theme.of(context).textTheme.bodySmall),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (_isSaas)
                  TextButton(onPressed: () => _invite(member), child: const Text('Invite')),
                TextButton(onPressed: () => _editMember(member), child: const Text('Edit')),
                TextButton(
                    onPressed: () => _deleteMember(member),
                    child: const Text('Delete',
                        style: TextStyle(color: Color(0xFFB3261E)))),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _invite(RecordItem member) async {
    final ok = await confirmDialog(
      context,
      title: 'Send invitation',
      message:
          'Email an invitation to ${member.str('email')} to join this workspace as ${member.str('position', 'team member')}?',
      confirmLabel: 'Send invite',
      danger: false,
    );
    if (!ok || !mounted) return;
    try {
      await widget.workspace.inviteTeamMember(member.id);
      if (mounted) showSnack(context, 'Invitation sent to ${member.str('email')}.');
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    }
  }

  Future<void> _deleteMember(RecordItem member) async {
    final ok = await confirmDialog(
      context,
      title: 'Remove team member',
      message:
          'Remove "${member.str('name')}" from the workspace? This also revokes their sign-in.',
      confirmLabel: 'Remove',
    );
    if (!ok || !mounted) return;
    try {
      await widget.workspace.remove('staff', member.id);
      if (mounted) showSnack(context, 'Team member removed.');
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    }
  }

  Future<void> _editMember(RecordItem? existing) async {
    final name = TextEditingController(text: existing?.str('name') ?? '');
    final email = TextEditingController(text: existing?.str('email') ?? '');
    final phone = TextEditingController(text: existing?.str('phone') ?? '');
    final position = TextEditingController(text: existing?.str('position') ?? '');
    final password = TextEditingController();
    final status =
        ValueNotifier<String>(existing?.str('status', 'Active') ?? 'Active');
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
                Text(existing == null ? 'Add team member' : 'Edit team member',
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
                        controller: position,
                        decoration: inputDecoration('Position', hint: 'Event manager'),
                        validator: (v) => requiredText(v, 'Position', max: 200),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: phone,
                        keyboardType: TextInputType.phone,
                        decoration: inputDecoration('Phone'),
                        validator: (v) => requiredText(v, 'Phone', max: 200),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ValueListenableBuilder<String>(
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
                if (existing == null && !_isSaas) ...[
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: password,
                    obscureText: true,
                    decoration: inputDecoration('Workspace password (optional)',
                        hint: 'At least 8 characters to create a sign-in'),
                    validator: (v) {
                      final text = v ?? '';
                      if (text.isEmpty) return null;
                      if (text.length < 8) return 'Use at least 8 characters.';
                      return null;
                    },
                  ),
                ],
                if (_isSaas) ...[
                  const SizedBox(height: 12),
                  const Text(
                    'After saving, use the mail icon on the member row to send an email invitation.',
                    style: TextStyle(fontSize: 12.5),
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
                                  'position': position.text.trim(),
                                  'status': status.value,
                                };
                                if (password.text.isNotEmpty) {
                                  body['loginPassword'] = password.text;
                                }
                                if (existing == null) {
                                  await widget.workspace.create('staff', body);
                                } else {
                                  await widget.workspace
                                      .update('staff', existing.id, body);
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
      showSnack(context, existing == null ? 'Team member added.' : 'Team member updated.');
    }
  }
}
