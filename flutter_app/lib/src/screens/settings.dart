import 'package:flutter/material.dart';

import '../core/api.dart';

import '../core/appearance.dart';
import '../core/session.dart';
import '../core/store.dart';
import '../widgets/common.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.session, required this.workspace, this.appearance});

  final SessionStore session;
  final WorkspaceStore workspace;
  final AppearanceStore? appearance;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _org;
  late final TextEditingController _server;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.session.user?.name ?? '');
    _org = TextEditingController(text: widget.session.user?.tenant ?? '');
    _server = TextEditingController(text: widget.session.baseUrl);
  }

  @override
  void dispose() {
    _name.dispose();
    _org.dispose();
    _server.dispose();
    super.dispose();
  }

  Future<void> _saveProfile() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    try {
      await widget.session.updateProfile(
        name: _name.text,
        organization:
            widget.session.user?.isOwner == true ? _org.text : null,
      );
      if (mounted) showSnack(context, 'Profile updated.');
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _changePassword() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Change password'),
        content: TextField(
          controller: controller,
          obscureText: true,
          autofocus: true,
          decoration: inputDecoration('New password',
              hint: widget.session.config.isSaas ? 'At least 12 characters' : 'At least 8 characters'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(controller.text),
              child: const Text('Update')),
        ],
      ),
    );
    if (result == null || result.isEmpty || !mounted) return;
    try {
      await widget.session.changePassword(result);
      if (mounted) showSnack(context, 'Password updated.');
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    }
  }

  Future<void> _saveServer() async {
    final value = _server.text.trim();
    if (value.isEmpty) return;
    await widget.session.setBaseUrl(value);
    if (mounted) {
      showSnack(context, 'Server updated: ${widget.session.baseUrl}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final user = session.user;
    final appearance = widget.appearance;
    return PageScaffold(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(context, 'Profile'),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextFormField(
                        controller: _name,
                        decoration: inputDecoration('Your name'),
                        validator: (v) => requiredText(v, 'Name', max: 120),
                      ),
                      if (user?.isOwner == true) ...[
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _org,
                          decoration: inputDecoration('Workspace / organization name'),
                          validator: (v) => requiredText(v, 'Workspace name', max: 120),
                        ),
                      ],
                      const SizedBox(height: 12),
                      TextFormField(
                        initialValue: user?.email ?? '',
                        readOnly: true,
                        decoration: inputDecoration('Email'),
                      ),
                      const SizedBox(height: 16),
                      Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton(
                          onPressed: _saving ? null : _saveProfile,
                          child: Text(_saving ? 'Saving…' : 'Save profile'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            _header(context, 'Security'),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.lock_outline),
                    title: const Text('Change password'),
                    subtitle: Text(session.config.isSaas
                        ? 'New password must be at least 12 characters'
                        : 'Password changes are handled by the demo server console'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: session.config.isSaas ? _changePassword : null,
                  ),
                  if (user?.platformAdmin == true && session.config.isSaas)
                    ListTile(
                      leading: const Icon(Icons.security_outlined),
                      title: const Text('Authenticator (MFA)'),
                      subtitle: const Text('Required for the platform console'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => MfaScreen(session: session)),
                      ),
                    ),
                ],
              ),
            ),
            if (appearance != null) ...[
              _header(context, 'Appearance'),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final entry in AppearanceStore.presetNames.entries)
                            ChoiceChip(
                              label: Text(entry.value),
                              selected: appearance.preset == entry.key,
                              onSelected: (_) => appearance.setPreset(entry.key),
                            ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      SegmentedButton<ThemeMode>(
                        segments: const [
                          ButtonSegment(value: ThemeMode.system, label: Text('System')),
                          ButtonSegment(value: ThemeMode.light, label: Text('Light')),
                          ButtonSegment(value: ThemeMode.dark, label: Text('Dark')),
                        ],
                        selected: {appearance.mode},
                        onSelectionChanged: (s) => appearance.setMode(s.first),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            _header(context, 'Server'),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      controller: _server,
                      decoration: inputDecoration('Base URL',
                          hint: 'https://venues.example.com'),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Mode: ${session.config.mode}'
                            '${session.config.billingEnabled ? ' · billing ${session.config.billingMode}' : ' · billing off'}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                        OutlinedButton(
                          onPressed: _saveServer,
                          child: const Text('Save & reconnect'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            _header(context, 'About'),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Gatherhall mobile & desktop app',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(
                      'Version 1.0.0 · connects to the Gatherhall Express API. '
                      'Role: ${user?.role ?? '—'} · workspace: ${user?.tenant ?? '—'}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (!session.config.isSaas) ...[
                      const SizedBox(height: 8),
                      const Text(
                        'Demo mode: data is disposable and never use it for real customer records.',
                        style: TextStyle(fontSize: 12.5, color: Color(0xFF9A6700)),
                      ),
                    ],
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        OutlinedButton.icon(
                          icon: const Icon(Icons.logout, size: 18),
                          label: const Text('Sign out'),
                          onPressed: () => session.logout(),
                        ),
                      ],
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

  Widget _header(BuildContext context, String title) => SectionHeader(title: title);
}

class MfaScreen extends StatefulWidget {
  const MfaScreen({super.key, required this.session});

  final SessionStore session;

  @override
  State<MfaScreen> createState() => _MfaScreenState();
}

class _MfaScreenState extends State<MfaScreen> {
  List<Map<String, dynamic>> _factors = <Map<String, dynamic>>[];
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _enrollment;
  final _code = TextEditingController();
  String? _verifyFactorId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _factors = await widget.session.mfaFactors();
      if (_factors.isNotEmpty) {
        _verifyFactorId = (_factors.first['id'] ?? '').toString();
      }
    } on ApiException catch (e) {
      _error = e.message;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _enroll() async {
    try {
      final result = await widget.session.mfaEnroll();
      setState(() => _enrollment = result);
      _verifyFactorId = (result['id'] ?? '').toString();
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    }
  }

  Future<void> _verify() async {
    final factorId = _verifyFactorId;
    final code = _code.text.trim();
    if (factorId == null || code.isEmpty) return;
    try {
      await widget.session.mfaVerify(factorId: factorId, code: code);
      if (mounted) {
        showSnack(context, 'Authenticator verified. Platform console unlocked.');
        Navigator.of(context).pop();
      }
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Authenticator (MFA)')),
      body: _loading
          ? const LoadingCenter()
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_error != null) ...[
                      ErrorBanner(message: _error!, onRetry: _load),
                      const SizedBox(height: 12),
                    ],
                    if (_factors.isEmpty) ...[
                      const Text(
                          'No authenticator factor is enrolled yet. Add one to protect platform administrator access.'),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Set up authenticator'),
                        onPressed: _enroll,
                      ),
                      if (_enrollment != null) ...[
                        const SizedBox(height: 14),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Add this secret to your authenticator app:',
                                    style: TextStyle(fontWeight: FontWeight.w700)),
                                const SizedBox(height: 8),
                                SelectableText('${_enrollment!['secret'] ?? ''}'),
                                const SizedBox(height: 8),
                                Text('Factor: ${_enrollment!['id'] ?? ''}',
                                    style: Theme.of(context).textTheme.bodySmall),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                    if (_factors.isNotEmpty) ...[
                      for (final f in _factors)
                        ListTile(
                          leading: const Icon(Icons.verified_user_outlined),
                          title: Text(f['name']?.toString() ?? 'Authenticator'),
                          subtitle: Text(f['status']?.toString() ?? ''),
                        ),
                      const SizedBox(height: 8),
                    ],
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _code,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      decoration: inputDecoration('6-digit code'),
                    ),
                    const SizedBox(height: 8),
                    FilledButton(
                      onPressed: _verify,
                      child: const Text('Verify code'),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Platform console access requires an aal2 (MFA) session on SaaS servers.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
