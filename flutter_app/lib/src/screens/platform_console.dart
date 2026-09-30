import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/formatters.dart';
import '../core/session.dart';
import '../core/store.dart';
import '../widgets/common.dart';

/// Platform operator console (SaaS mode, requires MFA).
class PlatformConsole extends StatefulWidget {
  const PlatformConsole({super.key, required this.session, required this.workspace});

  final SessionStore session;
  final WorkspaceStore workspace;

  @override
  State<PlatformConsole> createState() => _PlatformConsoleState();
}

class _PlatformConsoleState extends State<PlatformConsole> {
  int _tab = 0;
  bool _mfaRequired = false;

  @override
  Widget build(BuildContext context) {
    if (_mfaRequired) {
      return Scaffold(
        appBar: AppBar(title: const Text('Platform console')),
        body: _MfaGate(
          session: widget.session,
          onVerified: () => setState(() => _mfaRequired = false),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Platform console')),
      body: Column(
        children: [
          Material(
            color: Theme.of(context).colorScheme.surface,
            child: SafeArea(
              bottom: false,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    for (var i = 0; i < _tabs.length; i++)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: TextButton(
                          style: TextButton.styleFrom(
                            backgroundColor: i == _tab
                                ? Theme.of(context)
                                    .colorScheme
                                    .primaryContainer
                                : Colors.transparent,
                          ),
                          onPressed: () => setState(() => _tab = i),
                          child: Text(_tabs[i],
                              style: TextStyle(
                                  fontWeight:
                                      i == _tab ? FontWeight.w800 : FontWeight.w500)),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _tabContent(onMfaRequired: () => setState(() => _mfaRequired = true)),
          ),
        ],
      ),
    );
  }

  static const List<String> _tabs = <String>[
    'Overview',
    'Organizations',
    'Plans',
    'Website CMS',
    'Integrations',
    'Audit',
  ];

  Widget _tabContent({required VoidCallback onMfaRequired}) {
    switch (_tab) {
      case 0:
        return OverviewTab(
            session: widget.session, onMfaRequired: onMfaRequired);
      case 1:
        return OrganizationsTab(
            session: widget.session, onMfaRequired: onMfaRequired);
      case 2:
        return PlansTab(
            session: widget.session, onMfaRequired: onMfaRequired);
      case 3:
        return CmsTab(
            session: widget.session, onMfaRequired: onMfaRequired);
      case 4:
        return IntegrationsTab(
            session: widget.session, onMfaRequired: onMfaRequired);
      default:
        return OverviewTab(
            session: widget.session, onMfaRequired: onMfaRequired, auditOnly: true);
    }
  }
}

class _MfaGate extends StatelessWidget {
  const _MfaGate({required this.session, required this.onVerified});

  final SessionStore session;
  final VoidCallback onVerified;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.security_outlined, size: 42, color: Color(0xFF6A4BBC)),
              const SizedBox(height: 14),
              const Text('MFA required',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              const Text(
                'Platform administrator access needs a verified authenticator code.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () async {
                  final ok = await Navigator.of(context).push<bool>(
                    MaterialPageRoute(builder: (_) => MfaVerifyScreen(session: session)),
                  );
                  if (ok == true) onVerified();
                },
                child: const Text('Verify authenticator'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class MfaVerifyScreen extends StatefulWidget {
  const MfaVerifyScreen({super.key, required this.session});

  final SessionStore session;

  @override
  State<MfaVerifyScreen> createState() => _MfaVerifyScreenState();
}

class _MfaVerifyScreenState extends State<MfaVerifyScreen> {
  List<Map<String, dynamic>> _factors = <Map<String, dynamic>>[];
  String? _factorId;
  final _code = TextEditingController();
  String? _error;
  bool _loading = true;

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
        _factorId = (_factors.first['id'] ?? '').toString();
      }
    } on ApiException catch (e) {
      _error = e.message;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _verify() async {
    final factorId = _factorId;
    if (factorId == null || _code.text.trim().isEmpty) return;
    try {
      await widget.session.mfaVerify(
          factorId: factorId, code: _code.text.trim());
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Verify authenticator')),
      body: _loading
          ? const LoadingCenter()
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_error != null) ...[
                        ErrorBanner(message: _error!),
                        const SizedBox(height: 12),
                      ],
                      if (_factors.isEmpty)
                        const Text(
                            'No authenticator enrolled. Set one up from Settings → Security.'),
                      if (_factors.isNotEmpty) ...[
                        StatefulBuilder(builder: (setLocal) {
                          return DropdownButtonFormField<String>(
                            initialValue: _factorId,
                            decoration: inputDecoration('Authenticator'),
                            items: [
                              for (final f in _factors)
                                DropdownMenuItem(
                                  value: (f['id'] ?? '').toString(),
                                  child: Text(f['name']?.toString() ?? 'Authenticator'),
                                ),
                            ],
                            onChanged: (v) => setLocal(() => _factorId = v),
                          );
                        }),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _code,
                          keyboardType: TextInputType.number,
                          maxLength: 6,
                          decoration: inputDecoration('6-digit code'),
                        ),
                        const SizedBox(height: 8),
                        FilledButton(onPressed: _verify, child: const Text('Verify')),
                      ],
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}

class OverviewTab extends StatefulWidget {
  const OverviewTab({
    super.key,
    required this.session,
    required this.onMfaRequired,
    this.auditOnly = false,
  });

  final SessionStore session;
  final VoidCallback onMfaRequired;
  final bool auditOnly;

  @override
  State<OverviewTab> createState() => _OverviewTabState();
}

class _OverviewTabState extends State<OverviewTab> {
  Map<String, dynamic>? _overview;
  String? _error;
  bool _loading = true;

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
      _overview = await widget.session.api.getMap('/api/platform/overview');
    } on ApiException catch (e) {
      _error = e.message;
      if (e.status == 403 && e.message.contains('MFA')) {
        widget.onMfaRequired();
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _overview == null) return const LoadingCenter();
    if (_error != null && _overview == null) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: ErrorBanner(message: _error!, onRetry: _load),
      );
    }
    final data = _overview ?? <String, dynamic>{};
    final metrics = data['metrics'] is Map
        ? Map<String, dynamic>.from(data['metrics'] as Map)
        : <String, dynamic>{};
    final audit = (data['audit'] as List<dynamic>? ?? <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .toList();
    final limited = data['limited'] == true;

    if (widget.auditOnly) {
      return _auditList(context, audit, limited);
    }

    return PageScaffold(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (limited)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: ErrorBanner(
                  message: 'Metrics show at most 1,000 rows per dataset — truncated.'),
            ),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              SizedBox(
                width: 210,
                child: StatTile(
                  label: 'Organizations',
                  value: '${metrics['organizations'] ?? 0}',
                  icon: Icons.business_outlined,
                  caption: '${metrics['suspended'] ?? 0} suspended',
                ),
              ),
              SizedBox(
                width: 210,
                child: StatTile(
                  label: 'Active subscriptions',
                  value: '${metrics['activeSubscriptions'] ?? 0}',
                  icon: Icons.card_membership_outlined,
                  caption: '${metrics['trials'] ?? 0} in trial',
                  tone: const Color(0xFF1B7F4C),
                ),
              ),
              SizedBox(
                width: 210,
                child: StatTile(
                  label: 'Estimated MRR',
                  value: inr(((metrics['mrrPaise'] as num?) ?? 0) / 100),
                  icon: Icons.trending_up,
                  tone: const Color(0xFF1565C0),
                ),
              ),
              SizedBox(
                width: 210,
                child: StatTile(
                  label: 'Gross collected',
                  value: inr(((metrics['grossCollectedPaise'] as num?) ?? 0) / 100),
                  icon: Icons.account_balance_outlined,
                  tone: const Color(0xFF6A4BBC),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _organizationsCard(context, data),
          const SizedBox(height: 14),
          _auditCard(context, audit, limited),
        ],
      ),
    );
  }

  Widget _organizationsCard(BuildContext context, Map<String, dynamic> data) {
    final organizations = (data['organizations'] as List<dynamic>? ?? <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .toList();
    final subscriptions = (data['subscriptions'] as List<dynamic>? ?? <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .toList();
    final subsByTenant = <String, Map<String, dynamic>>{
      for (final s in subscriptions)
        if (s['tenant_id'] != null) (s['tenant_id'] as String): s,
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Organizations (${organizations.length})',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            if (organizations.isEmpty) const Text('No organizations yet.')
            else
              for (final org in organizations.take(50))
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: Icon(
                    org['status'] == 'suspended'
                        ? Icons.block
                        : Icons.check_circle_outline,
                    color: org['status'] == 'suspended'
                        ? const Color(0xFFB3261E)
                        : const Color(0xFF1B7F4C),
                  ),
                  title: Text(org['name']?.toString() ?? '',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(
                      '${org['city'] ?? ''} · ${org['billing_email'] ?? ''} · created ${formatDate(((org['created_at'] ?? '') as String).length >= 10 ? (org['created_at'] as String).substring(0, 10) : '')}'),
                  trailing: Text(
                    () {
                      final sub = subsByTenant[org['id']];
                      if (sub == null) return 'no subscription';
                      final status = sub['status']?.toString() ?? '';
                      final paid = sub['paid_through'];
                      return '$status${paid != null ? ' · paid to ${formatDate((paid as String).substring(0, paid.length >= 10 ? 10 : paid.length))}' : ''}';
                    }(),
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                  ),
                ),
          ],
        ),
      ),
    );
  }

  Widget _auditCard(BuildContext context, List<Map<String, dynamic>> audit, bool limited) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Recent audit events',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            _auditList(context, audit, limited),
          ],
        ),
      ),
    );
  }

  Widget _auditList(BuildContext context, List<Map<String, dynamic>> audit, bool limited) {
    if (audit.isEmpty) return const Text('No audit events.');
    return Column(
      children: [
        for (final row in audit.take(60))
          ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            leading: const Icon(Icons.history, size: 18),
            title: Text(row['action']?.toString() ?? '',
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
            subtitle: Text(
                '${formatDate(((row['created_at'] ?? '') as String).length >= 10 ? (row['created_at'] as String).substring(0, 10) : '')} · ${row['details'] ?? ''}',
                style: const TextStyle(fontSize: 12)),
          ),
        if (limited) const Text('Truncated to the latest 100 events.'),
      ],
    );
  }
}

class OrganizationsTab extends StatefulWidget {
  const OrganizationsTab({
    super.key,
    required this.session,
    required this.onMfaRequired,
  });

  final SessionStore session;
  final VoidCallback onMfaRequired;

  @override
  State<OrganizationsTab> createState() => _OrganizationsTabState();
}

class _OrganizationsTabState extends State<OrganizationsTab> {
  Map<String, dynamic>? _overview;
  String? _error;
  bool _loading = true;

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
      _overview = await widget.session.api.getMap('/api/platform/overview');
    } on ApiException catch (e) {
      _error = e.message;
      if (e.status == 403 && e.message.contains('MFA')) {
        widget.onMfaRequired();
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _setStatus(Map<String, dynamic> org) async {
    final suspending = org['status'] != 'suspended';
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(suspending ? 'Suspend organization' : 'Restore organization'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(suspending
                ? 'Suspending "${org['name']}" blocks workspace access. It does not cancel billing.'
                : 'Restore access for "${org['name']}".'),
            const SizedBox(height: 10),
            TextField(
              controller: controller,
              maxLines: 2,
              decoration: inputDecoration('Reason (5–500 characters)'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(suspending ? 'Suspend' : 'Restore')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.session.api.post('/api/platform/tenant-status', {
        'tenant_id': org['id'],
        'status': suspending ? 'suspended' : 'active',
        'reason': controller.text.trim(),
      });
      await _load();
      if (mounted) showSnack(context, 'Organization status updated.');
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    }
  }

  Future<void> _reconcile() async {
    final tenant = TextEditingController();
    final subscription = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reconcile checkout'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
                'Link an existing Razorpay subscription after an uncertain checkout.',
                style: TextStyle(fontSize: 13)),
            const SizedBox(height: 10),
            TextField(
                controller: tenant,
                decoration: const InputDecoration(labelText: 'Tenant (organization) UUID')),
            const SizedBox(height: 8),
            TextField(
                controller: subscription,
                decoration: const InputDecoration(labelText: 'Razorpay subscription ID (sub_…)')),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Reconcile')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.session.api.post('/api/platform/reconcile', {
        'tenantId': tenant.text.trim(),
        'subscriptionId': subscription.text.trim(),
      });
      if (mounted) showSnack(context, 'Checkout reconciled.');
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _overview == null) return const LoadingCenter();
    if (_error != null && _overview == null) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: ErrorBanner(message: _error!, onRetry: _load),
      );
    }
    final organizations = ((_overview?['organizations'] as List<dynamic>?) ?? <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .toList();
    return PageScaffold(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Organizations',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800)),
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.sync_problem, size: 18),
                label: const Text('Reconcile checkout'),
                onPressed: _reconcile,
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (final org in organizations)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                title: Text(org['name']?.toString() ?? '',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(
                    '${org['city'] ?? ''} · ${org['billing_email'] ?? ''} · ${org['status'] ?? ''}'),
                trailing: OutlinedButton(
                  onPressed: () => _setStatus(org),
                  child: Text(org['status'] == 'suspended' ? 'Restore' : 'Suspend'),
                ),
              ),
            ),
          if (organizations.isEmpty) const Text('No organizations.'),
        ],
      ),
    );
  }
}

class PlansTab extends StatefulWidget {
  const PlansTab({
    super.key,
    required this.session,
    required this.onMfaRequired,
  });

  final SessionStore session;
  final VoidCallback onMfaRequired;

  @override
  State<PlansTab> createState() => _PlansTabState();
}

class _PlansTabState extends State<PlansTab> {
  List<Map<String, dynamic>> _plans = <Map<String, dynamic>>[];
  bool _loading = true;
  String? _error;

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
      // The overview carries every plan (drafts included) through publicPlan().
      final overview =
          await widget.session.api.getMap('/api/platform/overview');
      final list = (overview['plans'] as List<dynamic>? ?? <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .toList();
      _plans = list;
    } on ApiException catch (e) {
      _error = e.message;
      if (e.status == 403 && e.message.contains('MFA')) {
        widget.onMfaRequired();
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _edit([Map<String, dynamic>? plan]) async {
    final name = TextEditingController(text: plan?['name']?.toString() ?? '');
    final description =
        TextEditingController(text: plan?['description']?.toString() ?? '');
    final monthly = TextEditingController(
        text: plan == null ? '' : '${((plan['monthly_paise'] as num?) ?? 0) / 100}');
    final yearly = TextEditingController(
        text: plan == null ? '' : '${((plan['yearly_paise'] as num?) ?? 0) / 100}');
    final halls = TextEditingController(text: '${plan?['max_halls'] ?? 3}');
    final staff = TextEditingController(text: '${plan?['max_staff'] ?? 5}');
    final trial = TextEditingController(text: '${plan?['trial_days'] ?? 0}');
    var published = plan?['published'] == true;
    final formKey = GlobalKey<FormState>();

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (setLocal) {
        return AlertDialog(
          title: Text(plan == null ? 'Add plan' : 'Edit plan'),
          content: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: name,
                    decoration: inputDecoration('Name'),
                    validator: (v) => requiredText(v, 'Name', max: 80),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: description,
                    maxLines: 2,
                    decoration: inputDecoration('Description'),
                    validator: (v) =>
                        (v ?? '').length > 400 ? 'Max 400 characters.' : null,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: monthly,
                          keyboardType:
                              const TextInputType.numberWithOptions(decimal: true),
                          decoration: inputDecoration('Monthly price (₹)'),
                          validator: (v) => numberText(v, 'Monthly price', min: 1),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextFormField(
                          controller: yearly,
                          keyboardType:
                              const TextInputType.numberWithOptions(decimal: true),
                          decoration: inputDecoration('Yearly price (₹)'),
                          validator: (v) => numberText(v, 'Yearly price', min: 1),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: halls,
                          keyboardType: TextInputType.number,
                          decoration: inputDecoration('Max halls'),
                          validator: (v) =>
                              numberText(v, 'Max halls', min: 1, max: 100, integer: true),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextFormField(
                          controller: staff,
                          keyboardType: TextInputType.number,
                          decoration: inputDecoration('Max staff'),
                          validator: (v) =>
                              numberText(v, 'Max staff', min: 1, max: 500, integer: true),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextFormField(
                          controller: trial,
                          keyboardType: TextInputType.number,
                          decoration: inputDecoration('Trial days'),
                          validator: (v) =>
                              numberText(v, 'Trial days', min: 0, max: 30, integer: true),
                        ),
                      ),
                    ],
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Published'),
                    value: published,
                    onChanged: (v) => setLocal(() => published = v),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Save')),
          ],
        );
      }),
    );
    if (saved != true || !mounted) return;
    if (!(formKey.currentState?.validate() ?? false)) return;
    final body = <String, dynamic>{
      if (plan?['id'] != null) 'id': plan!['id'],
      'name': name.text.trim(),
      'description': description.text.trim(),
      'monthly_paise': ((num.tryParse(monthly.text.trim()) ?? 0) * 100).round(),
      'yearly_paise': ((num.tryParse(yearly.text.trim()) ?? 0) * 100).round(),
      'max_halls': int.tryParse(halls.text.trim()) ?? 3,
      'max_staff': int.tryParse(staff.text.trim()) ?? 5,
      'trial_days': int.tryParse(trial.text.trim()) ?? 0,
      'published': published,
    };
    try {
      await widget.session.api.post('/api/platform/plans', body);
      await _load();
      if (mounted) showSnack(context, 'Plan saved.');
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _plans.isEmpty && _error == null) return const LoadingCenter();
    return PageScaffold(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Subscription plans',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800)),
              ),
              FilledButton.icon(
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add plan'),
                onPressed: () => _edit(),
              ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            ErrorBanner(message: _error!, onRetry: _load),
          ],
          const SizedBox(height: 10),
          for (final plan in _plans)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                title: Text(plan['name']?.toString() ?? '',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(
                    '₹${(((plan['monthly_paise'] as num?) ?? 0) / 100).toStringAsFixed(0)}/mo · '
                    '₹${(((plan['yearly_paise'] as num?) ?? 0) / 100).toStringAsFixed(0)}/yr · '
                    '${plan['max_halls']} halls · ${plan['max_staff']} staff · v${plan['version'] ?? 1}'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    StatusChip(
                        label: plan['published'] == true ? 'Published' : 'Draft',
                        tone: plan['published'] == true ? 'green' : 'amber'),
                    IconButton(
                      icon: const Icon(Icons.edit_outlined, size: 19),
                      onPressed: () => _edit(plan),
                    ),
                  ],
                ),
              ),
            ),
          if (_plans.isEmpty && _error == null)
            const Text('No plans returned. Published plans appear here; drafts are managed from the web console.'),
        ],
      ),
    );
  }
}

class CmsTab extends StatefulWidget {
  const CmsTab({
    super.key,
    required this.session,
    required this.onMfaRequired,
  });

  final SessionStore session;
  final VoidCallback onMfaRequired;

  @override
  State<CmsTab> createState() => _CmsTabState();
}

class _CmsTabState extends State<CmsTab> {
  List<Map<String, dynamic>> _entries = <Map<String, dynamic>>[];
  bool _loading = true;
  String? _error;

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
      final list = await widget.session.api.getList('/api/platform/cms');
      _entries = list.whereType<Map<String, dynamic>>().toList();
    } on ApiException catch (e) {
      _error = e.message;
      if (e.status == 403 && e.message.contains('MFA')) {
        widget.onMfaRequired();
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _docField(Map<String, dynamic> entry, String key) {
    final doc = entry['draft'] ?? entry['published'];
    if (doc is Map && doc[key] != null) return doc[key].toString();
    return '';
  }

  Future<void> _edit(Map<String, dynamic> entry) async {
    final draft = entry['draft'] is Map
        ? Map<String, dynamic>.from(entry['draft'] as Map)
        : <String, dynamic>{};
    final title = TextEditingController(text: draft['title']?.toString() ?? '');
    final summary = TextEditingController(text: draft['summary']?.toString() ?? '');
    final body = TextEditingController(text: draft['body']?.toString() ?? '');
    final seoTitle = TextEditingController(text: draft['seo_title']?.toString() ?? '');
    final seoDescription =
        TextEditingController(text: draft['seo_description']?.toString() ?? '');
    final category = TextEditingController(text: draft['category']?.toString() ?? '');

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${entry['kind']} · ${entry['slug']} · ${entry['locale']}'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                  controller: title,
                  decoration: inputDecoration('Title'),
                  maxLength: 180),
              TextField(
                  controller: summary,
                  maxLines: 2,
                  decoration: inputDecoration('Summary')),
              TextField(
                  controller: body,
                  maxLines: 8,
                  decoration: inputDecoration('Body (markdown-ish text)')),
              TextField(
                  controller: category, decoration: inputDecoration('Category')),
              TextField(
                  controller: seoTitle,
                  decoration: inputDecoration('SEO title'),
                  maxLength: 180),
              TextField(
                  controller: seoDescription,
                  maxLines: 2,
                  decoration: inputDecoration('SEO description')),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Save draft')),
        ],
      ),
    );
    if (saved != true || !mounted) return;
    try {
      await widget.session.api.post('/api/platform/cms/save', {
        'id': entry['id'],
        'revision': entry['revision'],
        'kind': entry['kind'],
        'slug': entry['slug'],
        'locale': entry['locale'],
        'draft': {
          'title': title.text.trim(),
          'summary': summary.text.trim(),
          'body': body.text.trim(),
          'seo_title': seoTitle.text.trim(),
          'seo_description': seoDescription.text.trim(),
          'category': category.text.trim(),
        },
      });
      await _load();
      if (mounted) showSnack(context, 'Draft saved.');
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    }
  }

  Future<void> _action(Map<String, dynamic> entry, String action) async {
    try {
      await widget.session.api.post('/api/platform/cms/action', {
        'id': entry['id'],
        'revision': entry['revision'],
        'action': action,
      });
      await _load();
      if (mounted) showSnack(context, 'CMS ${action} completed.');
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _entries.isEmpty && _error == null) return const LoadingCenter();
    return PageScaffold(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Website CMS (${_entries.length})',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800)),
              ),
              IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            ErrorBanner(message: _error!, onRetry: _load),
          ],
          const SizedBox(height: 10),
          for (final entry in _entries)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        StatusChip(
                            label: (entry['kind'] ?? '').toString(),
                            tone: entry['kind'] == 'blog' ? 'purple' : 'blue'),
                        const SizedBox(width: 6),
                        StatusChip(label: (entry['locale'] ?? '').toString(), tone: 'grey'),
                        const SizedBox(width: 6),
                        StatusChip(
                            label: entry['published'] != null ? 'Published' : 'Draft',
                            tone: entry['published'] != null ? 'green' : 'amber'),
                        const Spacer(),
                        Text('rev ${entry['revision'] ?? 1}',
                            style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text('${entry['slug']} — ${_docField(entry, 'title')}',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text(_docField(entry, 'summary'),
                        style: Theme.of(context).textTheme.bodySmall,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                            onPressed: () => _edit(entry),
                            child: const Text('Edit draft')),
                        if (entry['published'] == null)
                          TextButton(
                              onPressed: () => _action(entry, 'publish'),
                              child: const Text('Publish'))
                        else
                          TextButton(
                              onPressed: () => _action(entry, 'unpublish'),
                              child: const Text('Unpublish')),
                        TextButton(
                          onPressed: () => _action(entry, 'delete'),
                          child: const Text('Delete',
                              style: TextStyle(color: Color(0xFFB3261E))),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          if (_entries.isEmpty && _error == null)
            const Text('No CMS entries. Apply the website CMS migration on the server.'),
          const SizedBox(height: 16),
          EnquiriesSection(session: widget.session),
        ],
      ),
    );
  }
}

class EnquiriesSection extends StatefulWidget {
  const EnquiriesSection({super.key, required this.session});

  final SessionStore session;

  @override
  State<EnquiriesSection> createState() => _EnquiriesSectionState();
}

class _EnquiriesSectionState extends State<EnquiriesSection> {
  List<Map<String, dynamic>> _rows = <Map<String, dynamic>>[];
  bool _loading = true;
  String? _error;

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
      final list =
          await widget.session.api.getList('/api/platform/enquiries');
      _rows = list.whereType<Map<String, dynamic>>().toList();
    } on ApiException catch (e) {
      _error = e.message;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _action(Map<String, dynamic> row, String action) async {
    try {
      await widget.session.api.post('/api/platform/enquiries/action', {
        'id': row['id'],
        'action': action,
      });
      await _load();
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _rows.isEmpty && _error == null) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: LinearProgressIndicator(minHeight: 3),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Contact enquiries (${_rows.length})',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        if (_error != null) ErrorBanner(message: _error!, onRetry: _load),
        for (final row in _rows)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                            '${row['name'] ?? ''} · ${row['email'] ?? ''}',
                            style:
                                const TextStyle(fontWeight: FontWeight.w700)),
                      ),
                      StatusChip(
                          label: (row['status'] ?? 'new').toString(),
                          tone: row['status'] == 'closed' ? 'grey' : 'blue'),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(row['message']?.toString() ?? ''),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                          onPressed: () => _action(row, 'read'),
                          child: const Text('Mark read')),
                      TextButton(
                          onPressed: () => _action(row, 'closed'),
                          child: const Text('Close')),
                      TextButton(
                        onPressed: () => _action(row, 'delete'),
                        child: const Text('Delete',
                            style: TextStyle(color: Color(0xFFB3261E))),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        if (_rows.isEmpty && _error == null)
          const Text('No website enquiries yet.'),
      ],
    );
  }
}

class IntegrationsTab extends StatefulWidget {
  const IntegrationsTab({
    super.key,
    required this.session,
    required this.onMfaRequired,
  });

  final SessionStore session;
  final VoidCallback onMfaRequired;

  @override
  State<IntegrationsTab> createState() => _IntegrationsTabState();
}

class _IntegrationsTabState extends State<IntegrationsTab> {
  Map<String, dynamic>? _data;
  bool _loading = true;
  String? _error;
  bool _saving = false;

  static const Map<String, String> _labels = <String, String>{
    'razorpay': 'Payment gateway · Razorpay',
    'email': 'Email · SMTP',
    'sms': 'SMS · MSG91',
    'whatsapp': 'WhatsApp · Meta Cloud API',
  };

  static const Map<String, List<Map<String, dynamic>>> _kinds =
      <String, List<Map<String, dynamic>>>{
    'razorpay': [
      {'key': 'keyId', 'label': 'Key ID', 'secret': false},
      {'key': 'keySecret', 'label': 'Key secret', 'secret': true},
      {'key': 'webhookSecret', 'label': 'Webhook secret', 'secret': true},
    ],
    'email': [
      {'key': 'host', 'label': 'SMTP host', 'secret': false},
      {'key': 'port', 'label': 'Port (465 or 587)', 'secret': false},
      {'key': 'user', 'label': 'Username', 'secret': false},
      {'key': 'password', 'label': 'Password', 'secret': true},
      {'key': 'from', 'label': 'Verified sender email', 'secret': false},
    ],
    'sms': [
      {'key': 'authKey', 'label': 'Auth key', 'secret': true},
      {'key': 'flowId', 'label': 'Approved flow ID', 'secret': false},
      {'key': 'approved', 'label': 'Type "true" to confirm DLT approval', 'secret': false},
    ],
    'whatsapp': [
      {'key': 'token', 'label': 'Permanent access token', 'secret': true},
      {'key': 'phoneId', 'label': 'Phone number ID', 'secret': false},
      {'key': 'template', 'label': 'Approved template name', 'secret': false},
      {'key': 'language', 'label': 'Template language (e.g. en)', 'secret': false},
      {'key': 'approved', 'label': 'Type "true" to confirm template approval', 'secret': false},
    ],
  };

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
      _data = await widget.session.api.getMap('/api/platform/settings');
    } on ApiException catch (e) {
      _error = e.message;
      if (e.status == 403 && e.message.contains('MFA')) {
        widget.onMfaRequired();
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save(String kind) async {
    final settings = _data?['settings'];
    if (settings is! Map || settings[kind] is! Map) return;
    final config = Map<String, dynamic>.from(settings[kind] as Map);
    final existingFields = config['fields'] is Map
        ? Map<String, dynamic>.from(config['fields'] as Map)
        : <String, dynamic>{};
    final enabled = config['enabled'] == true;
    final revision = (config['revision'] as num?)?.toInt() ?? 0;

    final controllers = <String, TextEditingController>{};
    for (final field in _kinds[kind]!) {
      final key = field['key']! as String;
      final secret = field['secret'] == true;
      controllers[key] = TextEditingController(
          text: secret ? '' : (existingFields[key]?.toString() ?? ''));
    }
    final enabledNotifier = ValueNotifier<bool>(enabled);

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (setLocal) {
        return AlertDialog(
          title: Text(_labels[kind] ?? kind),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Enabled'),
                  value: enabledNotifier.value,
                  onChanged: (v) => setLocal(() => enabledNotifier.value = v),
                ),
                for (final field in _kinds[kind]!)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: TextField(
                      controller: controllers[field['key']! as String],
                      obscureText: field['secret'] == true,
                      decoration: InputDecoration(
                        labelText: field['label']! as String,
                        helperText: field['secret'] == true
                            ? 'Leave blank to keep the saved secret'
                            : null,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Save')),
          ],
        );
      }),
    );
    if (saved != true || !mounted) return;

    final fields = <String, String>{};
    for (final field in _kinds[kind]!) {
      final key = field['key']! as String;
      final value = controllers[key]!.text.trim();
      if (field['secret'] == true && value.isEmpty) continue;
      fields[key] = value;
    }
    setState(() => _saving = true);
    try {
      await widget.session.api.post('/api/platform/settings/$kind', {
        'enabled': enabledNotifier.value,
        'revision': revision,
        'fields': fields,
      });
      await _load();
      if (mounted) showSnack(context, 'Settings saved.');
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
    for (final c in controllers.values) {
      c.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _data == null) return const LoadingCenter();
    if (_error != null && _data == null) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: ErrorBanner(message: _error!, onRetry: _load),
      );
    }
    final settings = _data?['settings'] is Map
        ? Map<String, dynamic>.from(_data!['settings'] as Map)
        : <String, dynamic>{};
    final runtime = _data?['runtimeBilling'] is Map
        ? Map<String, dynamic>.from(_data!['runtimeBilling'] as Map)
        : <String, dynamic>{};
    final encryptionReady = _data?['encryptionReady'] == true;

    return PageScaffold(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!encryptionReady)
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: ErrorBanner(
                    message:
                        'INTEGRATION_ENCRYPTION_KEY is not configured on the server. Provider secrets stay locked until it is set.'),
              ),
            if (runtime.isNotEmpty)
              Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Text(
                  'Runtime billing: ${runtime['mode'] ?? 'off'}'
                  '${runtime['restartRequired'] == true ? ' · restart required after saving' : ''}'
                  ' · source: ${_data?['razorpaySource'] ?? ''}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            for (final kind in _labels.keys) _kindCard(kind, settings[kind]),
            if (_saving) const LinearProgressIndicator(minHeight: 3),
          ],
        ),
      ),
    );
  }

  Widget _kindCard(String kind, dynamic raw) {
    final config = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
    final enabled = config['enabled'] == true;
    final updatedAt = config['updatedAt']?.toString();
    final secrets = config['secrets'] is Map
        ? Map<String, dynamic>.from(config['secrets'] as Map)
        : <String, dynamic>{};
    final savedSecrets = secrets.values.where((v) => v == true).length;
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
                  child: Text(_labels[kind] ?? kind,
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                ),
                StatusChip(
                    label: enabled ? 'Enabled' : 'Disabled',
                    tone: enabled ? 'green' : 'grey'),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: _saving ? null : () => _save(kind),
                  child: const Text('Configure'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              [
                if (updatedAt != null && updatedAt.isNotEmpty)
                  'Updated ${formatDate(updatedAt.substring(0, updatedAt.length >= 10 ? 10 : updatedAt.length))}',
                '$savedSecrets secrets saved',
              ].join(' · '),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
