import 'package:flutter/material.dart';

import '../core/api.dart';

import '../core/session.dart';
import '../core/store.dart';
import '../widgets/common.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, required this.session, required this.workspace});

  final SessionStore session;
  final WorkspaceStore workspace;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _organization = TextEditingController();
  bool _registerMode = false;
  bool _busy = false;
  String? _info;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _organization.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _error = null;
      _info = null;
    });
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _busy = true);
    try {
      if (_registerMode) {
        final message = widget.session.config.isSaas
            ? await widget.session.registerSaas(
                name: _name.text,
                email: _email.text,
                password: _password.text,
              )
            : await widget.session.registerDemo(
                name: _name.text,
                email: _email.text,
                password: _password.text,
                organization: _organization.text,
              );
        if (widget.session.config.isSaas) {
          setState(() {
            _registerMode = false;
            _info = message;
            _password.clear();
          });
        } else {
          await widget.workspace.load();
        }
      } else {
        await widget.session.login(_email.text, _password.text);
        if (widget.session.user?.inWorkspace == true) {
          await widget.workspace.load();
        }
      }
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _forgot() async {
    final controller = TextEditingController(text: _email.text.trim());
    final email = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset password'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.emailAddress,
          decoration: inputDecoration('Email'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
              child: const Text('Send link')),
        ],
      ),
    );
    if (email == null || email.isEmpty || !mounted) return;
    try {
      final message = await widget.session.forgotPassword(email);
      if (mounted) showSnack(context, message);
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final config = widget.session.config;
    final width = MediaQuery.sizeOf(context).width;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: scheme.primaryContainer,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(Icons.local_florist,
                            color: scheme.onPrimaryContainer, size: 26),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Gatherhall',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleLarge
                                    ?.copyWith(fontWeight: FontWeight.w800)),
                            Text(
                              config.isSaas
                                  ? 'Venue management platform'
                                  : 'Venue management demo workspace',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: scheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Server settings',
                        onPressed: _serverSheet,
                        icon: const Icon(Icons.dns_outlined),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              _registerMode ? 'Create your account' : 'Sign in',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 16),
                            if (_registerMode) ...[
                              TextFormField(
                                controller: _name,
                                textInputAction: TextInputAction.next,
                                decoration: inputDecoration('Full name',
                                    prefixIcon: Icons.person_outline),
                                validator: (v) => requiredText(v, 'Name', max: 120),
                              ),
                              const SizedBox(height: 12),
                            ],
                            TextFormField(
                              controller: _email,
                              keyboardType: TextInputType.emailAddress,
                              textInputAction: TextInputAction.next,
                              decoration: inputDecoration('Email',
                                  prefixIcon: Icons.mail_outline),
                              validator: emailText,
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _password,
                              obscureText: true,
                              onFieldSubmitted: (_) => _submit(),
                              decoration: inputDecoration('Password',
                                  prefixIcon: Icons.lock_outline,
                                  hint: _registerMode
                                      ? (config.isSaas
                                          ? 'At least 12 characters'
                                          : 'At least 8 characters')
                                      : null),
                              validator: (v) {
                                final text = v ?? '';
                                if (text.isEmpty) return 'Password is required.';
                                if (_registerMode) {
                                  final min = config.isSaas ? 12 : 8;
                                  if (text.length < min) {
                                    return 'Use at least $min characters.';
                                  }
                                }
                                return null;
                              },
                            ),
                            if (_registerMode && !config.isSaas) ...[
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _organization,
                                textInputAction: TextInputAction.done,
                                decoration: inputDecoration('Workspace / venue name',
                                    prefixIcon: Icons.business_outlined),
                                validator: (v) => requiredText(v, 'Workspace name', max: 120),
                              ),
                            ],
                            const SizedBox(height: 14),
                            if (_error != null) ...[
                              ErrorBanner(message: _error!),
                              const SizedBox(height: 12),
                            ],
                            if (_info != null) ...[
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFE7F6EE),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(_info!,
                                    style: const TextStyle(color: Color(0xFF145C37))),
                              ),
                              const SizedBox(height: 12),
                            ],
                            FilledButton(
                              onPressed: _busy ? null : _submit,
                              child: _busy
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(strokeWidth: 2))
                                  : Text(_registerMode ? 'Create account' : 'Sign in'),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: TextButton(
                                    onPressed: _busy
                                        ? null
                                        : () => setState(() {
                                              _registerMode = !_registerMode;
                                              _error = null;
                                              _info = null;
                                            }),
                                    child: Text(_registerMode
                                        ? 'Have an account? Sign in'
                                        : 'New here? Create an account'),
                                  ),
                                ),
                                if (!_registerMode)
                                  TextButton(
                                    onPressed: _busy ? null : _forgot,
                                    child: const Text('Forgot?'),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (config.isSaas && !config.registrationEnabled)
                    const Text(
                      'Registration is currently closed on this server.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12.5),
                    ),
                  if (!config.isSaas) ...[
                    const Text(
                      'Demo accounts — password: Welcome123!',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      alignment: WrapAlignment.center,
                      children: [
                        _demoChip('owner@gatherhall.demo'),
                        _demoChip('staff@gatherhall.demo'),
                        _demoChip('client@gatherhall.demo'),
                        _demoChip('willow@gatherhall.demo'),
                      ],
                    ),
                  ],
                  if (width > 520) const SizedBox(height: 8),
                  Text(
                    'Server: ${widget.session.baseUrl}',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _demoChip(String email) {
    return ActionChip(
      avatar: const Icon(Icons.person, size: 16),
      label: Text(email, style: const TextStyle(fontSize: 12)),
      onPressed: () {
        _email.text = email;
        _password.text = 'Welcome123!';
        setState(() => _registerMode = false);
      },
    );
  }

  Future<void> _serverSheet() async {
    final controller = TextEditingController(text: widget.session.baseUrl);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Server address'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Base URL of the Gatherhall API server.',
                style: TextStyle(fontSize: 13)),
            const SizedBox(height: 10),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: inputDecoration('http://localhost:3000'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
              child: const Text('Save')),
        ],
      ),
    );
    if (result != null && result.isNotEmpty && mounted) {
      await widget.session.setBaseUrl(result);
    }
  }
}

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.session});

  final SessionStore session;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _city = TextEditingController();
  String? _planId;
  String _interval = 'monthly';
  bool _busy = false;
  String? _error;
  List<Map<String, dynamic>> _plans = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _invitations = <Map<String, dynamic>>[];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _city.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final plans = await widget.session.api.getList('/api/public/plans');
      _plans = plans.whereType<Map<String, dynamic>>().toList();
      if (_plans.isNotEmpty && _planId == null) {
        _planId = _plans.first['id'] as String?;
      }
      _invitations = await widget.session.invitations();
      _error = null;
    } on ApiException catch (e) {
      _error = e.message;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _registerOrg() async {
    setState(() => _error = null);
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_planId == null) {
      setState(() => _error = 'Choose a subscription plan.');
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.session.acceptOrganization(
        name: _name.text,
        phone: _phone.text,
        city: _city.text,
        planId: _planId!,
        interval: _interval,
      );
      if (mounted) {
        showSnack(context,
            'Organization registered. Start checkout from Billing to activate it.');
      }
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _accept(String invitationId) async {
    setState(() => _busy = true);
    try {
      await widget.session.acceptInvitation(invitationId);
      if (mounted) showSnack(context, 'Invitation accepted.');
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final user = widget.session.user;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Set up your account'),
        actions: [
          IconButton(
            tooltip: 'Sign out',
            onPressed: () => widget.session.logout(),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: _loading
          ? const LoadingCenter()
          : Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Welcome${user == null ? '' : ', ${user.name}'}',
                        style: Theme.of(context)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Join an organization you were invited to, or register a new venue workspace with a subscription plan.',
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 16),
                      if (_invitations.isNotEmpty) ...[
                        const SectionHeader(title: 'Pending invitations'),
                        for (final invite in _invitations)
                          Card(
                            child: ListTile(
                              leading: const Icon(Icons.mail_outline),
                              title: Text(
                                  (invite['organizations'] is Map
                                      ? ((invite['organizations'] as Map)['name'] ?? '')
                                          .toString()
                                      : 'Organization'),
                                  style: const TextStyle(fontWeight: FontWeight.w700)),
                              subtitle: Text(
                                  'Role: ${invite['role'] ?? ''} · expires ${invite['expires_at'] ?? ''}'),
                              trailing: FilledButton(
                                onPressed: _busy ? null : () => _accept(invite['id'] as String),
                                child: const Text('Accept'),
                              ),
                            ),
                          ),
                        const SizedBox(height: 16),
                      ],
                      const SectionHeader(title: 'Register a new organization'),
                      if (_error != null) ...[
                        ErrorBanner(message: _error!),
                        const SizedBox(height: 12),
                      ],
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
                                  decoration:
                                      inputDecoration('Organization name', prefixIcon: Icons.business),
                                  validator: (v) => requiredText(v, 'Organization name', min: 2, max: 120),
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextFormField(
                                        controller: _phone,
                                        keyboardType: TextInputType.phone,
                                        decoration: inputDecoration('Phone'),
                                        validator: (v) =>
                                            requiredText(v, 'Phone', max: 30),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: TextFormField(
                                        controller: _city,
                                        decoration: inputDecoration('City'),
                                        validator: (v) =>
                                            requiredText(v, 'City', max: 80),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                if (_plans.isEmpty)
                                  const Text('No published plans are available yet.')
                                else ...[
                                  Text('Plan',
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelLarge
                                          ?.copyWith(fontWeight: FontWeight.w700)),
                                  const SizedBox(height: 8),
                                  for (final plan in _plans) _planTile(plan),
                                  const SizedBox(height: 12),
                                  SegmentedButton<String>(
                                    segments: const [
                                      ButtonSegment(value: 'monthly', label: Text('Monthly')),
                                      ButtonSegment(value: 'yearly', label: Text('Yearly')),
                                    ],
                                    selected: {_interval},
                                    onSelectionChanged: (s) =>
                                        setState(() => _interval = s.first),
                                  ),
                                ],
                                const SizedBox(height: 18),
                                FilledButton(
                                  onPressed: _busy ? null : _registerOrg,
                                  child: Text(_busy
                                      ? 'Working…'
                                      : 'Register organization'),
                                ),
                                if (!widget.session.config.billingEnabled)
                                  const Padding(
                                    padding: EdgeInsets.only(top: 10),
                                    child: Text(
                                      'Billing is not configured on this server yet; organization registration may be unavailable.',
                                      style: TextStyle(fontSize: 12.5),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Widget _planTile(Map<String, dynamic> plan) {
    final id = plan['id'] as String? ?? '';
    final selected = _planId == id;
    final monthly = ((plan['monthly_paise'] as num?) ?? 0) / 100;
    final yearly = ((plan['yearly_paise'] as num?) ?? 0) / 100;
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
        onTap: () => setState(() => _planId = id),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(selected ? Icons.radio_button_checked : Icons.radio_button_off,
                  color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(plan['name']?.toString() ?? '',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text(
                      plan['description']?.toString() ?? '',
                      style: Theme.of(context).textTheme.bodySmall,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '₹${monthly.toStringAsFixed(0)}/mo · ₹${yearly.toStringAsFixed(0)}/yr · '
                      '${plan['max_halls'] ?? '?'} halls · ${plan['max_staff'] ?? '?'} staff'
                      '${((plan['trial_days'] as num?) ?? 0) > 0 ? ' · ${plan['trial_days']}-day trial' : ''}',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
