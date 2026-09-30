import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/formatters.dart';
import '../core/session.dart';
import '../widgets/common.dart';

/// Public discovery flow (no sign-in required):
///   HallExplorerScreen → HallDetailScreen → HallEnquiryScreen
/// Backed by `/api/public/halls`, `/api/public/content` and
/// `/api/public/enquiries` on the demo and SaaS servers.
class HallExplorerScreen extends StatefulWidget {
  const HallExplorerScreen({super.key, required this.session});

  final SessionStore session;

  @override
  State<HallExplorerScreen> createState() => _HallExplorerScreenState();
}

class _HallExplorerScreenState extends State<HallExplorerScreen> {
  List<Map<String, dynamic>> _halls = <Map<String, dynamic>>[];
  List<String> _cities = <String>[];
  String _city = '';
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
      final json = await widget.session.api.getMap('/api/public/halls');
      final halls = (json['halls'] as List<dynamic>? ?? <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .toList();
      final cities = (json['cities'] as List<dynamic>? ?? <dynamic>[])
          .map((dynamic c) => c.toString())
          .toList();
      if (!mounted) return;
      setState(() {
        _halls = halls;
        _cities = cities;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  List<Map<String, dynamic>> get _filtered =>
      _city.isEmpty ? _halls : _halls.where((h) => h['city'] == _city).toList();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Wedding halls'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: Builder(builder: (context) {
        if (_loading) return const LoadingCenter(label: 'Finding halls near you…');
        if (_error != null) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: ErrorBanner(message: _error!, onRetry: _load),
            ),
          );
        }
        if (_halls.isEmpty) {
          return const EmptyState(
            icon: Icons.search_off_outlined,
            title: 'No halls listed yet',
            message:
                'Halls will appear here as soon as venues join Gatherhall in your area.',
          );
        }
        return Column(
          children: [
            if (_cities.isNotEmpty)
              SizedBox(
                height: 56,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        label: const Text('All areas'),
                        selected: _city.isEmpty,
                        onSelected: (_) => setState(() => _city = ''),
                      ),
                    ),
                    ..._cities.map(
                      (city) => Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: FilterChip(
                          label: Text(city),
                          selected: _city == city,
                          onSelected: (_) => setState(() => _city = city),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: _filtered.isEmpty
                  ? EmptyState(
                      icon: Icons.location_off_outlined,
                      title: 'No halls in $_city',
                      message: 'Try another area to see more venues.',
                      action: TextButton(
                        onPressed: () => setState(() => _city = ''),
                        child: const Text('Show all areas'),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      itemCount: _filtered.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, index) => _HallCard(
                        session: widget.session,
                        hall: _filtered[index],
                      ),
                    ),
            ),
          ],
        );
      }),
    );
  }
}

class _HallCard extends StatelessWidget {
  const _HallCard({required this.session, required this.hall});

  final SessionStore session;
  final Map<String, dynamic> hall;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final capacity = _num(hall, 'capacity').round();
    final price = _num(hall, 'price');
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          Navigator.of(context).push<void>(
            MaterialPageRoute<void>(
              builder: (_) => HallDetailScreen(session: session, hall: hall),
            ),
          );
        },
        child: Row(
          children: [
            Container(
              width: 96,
              height: 128,
              color: scheme.primaryContainer,
              child:
                  Icon(_typeIconOf(hall), size: 40, color: scheme.onPrimaryContainer),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _str(hall, 'venue', 'Venue'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.labelMedium?.copyWith(color: scheme.primary),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _str(hall, 'name', 'Hall'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          text.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 10,
                      runSpacing: 4,
                      children: [
                        _metaChip(context, Icons.place_outlined,
                            _str(hall, 'city', 'Any area')),
                        _metaChip(
                            context,
                            Icons.people_outline,
                            capacity > 0
                                ? '$capacity guests'
                                : 'Capacity on request'),
                        _metaChip(
                            context, Icons.category_outlined, _str(hall, 'type', 'Hall')),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      price > 0 ? 'From ${inr(price)} / day' : 'Contact for pricing',
                      style: text.labelLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: scheme.tertiary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Icon(Icons.chevron_right, color: scheme.outline),
            ),
          ],
        ),
      ),
    );
  }

  Widget _metaChip(BuildContext context, IconData icon, String label) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 3),
        Text(label,
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: color)),
      ],
    );
  }
}

class HallDetailScreen extends StatefulWidget {
  const HallDetailScreen({super.key, required this.session, required this.hall});

  final SessionStore session;
  final Map<String, dynamic> hall;

  @override
  State<HallDetailScreen> createState() => _HallDetailScreenState();
}

class _HallDetailScreenState extends State<HallDetailScreen> {
  Map<String, dynamic> _detail = <String, dynamic>{};
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
      final json =
          await widget.session.api.getMap('/api/public/halls/${widget.hall['id']}');
      if (!mounted) return;
      setState(() {
        _detail = json;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final hall = (_detail['hall'] as Map<String, dynamic>?) ??
        <String, dynamic>{...widget.hall};
    final addons = (_detail['addons'] as List<dynamic>? ?? <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .toList();
    final plans = (_detail['plans'] as List<dynamic>? ?? <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .toList();
    return Scaffold(
      appBar: AppBar(title: Text(_str(widget.hall, 'name', 'Hall'))),
      body: _loading
          ? const LoadingCenter(label: 'Loading hall…')
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: ErrorBanner(message: _error!, onRetry: _load),
                  ),
                )
              : PageScaffold(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: scheme.primaryContainer,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_str(hall, 'venue', 'Venue'),
                                style: text.labelLarge
                                    ?.copyWith(color: scheme.onPrimaryContainer)),
                            const SizedBox(height: 4),
                            Text(_str(hall, 'name', 'Hall'),
                                style: text.headlineSmall
                                    ?.copyWith(fontWeight: FontWeight.w800)),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 12,
                              runSpacing: 6,
                              children: [
                                _fact(context, Icons.place_outlined,
                                    _str(hall, 'city', 'Any area')),
                                _fact(context, Icons.people_outline,
                                    '${_num(hall, 'capacity').round()} guests'),
                                _fact(context, Icons.category_outlined,
                                    _str(hall, 'type', 'Hall')),
                              ],
                            ),
                          ],
                        ),
                      ),
                      if (_str(hall, 'description').isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text(_str(hall, 'description'),
                            style: text.bodyMedium?.copyWith(height: 1.5)),
                      ],
                      const SectionHeader(title: 'Hall rates'),
                      _rates(hall),
                      if (plans.isNotEmpty) ...[
                        const SectionHeader(title: 'Pricing models'),
                        ...plans.map(_planTile),
                      ],
                      if (addons.isNotEmpty) ...[
                        const SectionHeader(title: 'Services & add-ons'),
                        ...addons.map(_addonTile),
                      ],
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: () {
                            Navigator.of(context).push<void>(
                              MaterialPageRoute<void>(
                                builder: (_) => HallEnquiryScreen(
                                    session: widget.session, hall: hall),
                              ),
                            );
                          },
                          icon: const Icon(Icons.mail_outline),
                          label: const Text('Send an enquiry'),
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
    );
  }

  Widget _fact(BuildContext context, IconData icon, String label) {
    final color = Theme.of(context).colorScheme.onPrimaryContainer;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 4),
        Text(label,
            style:
                Theme.of(context).textTheme.labelMedium?.copyWith(color: color)),
      ],
    );
  }

  Widget _rates(Map<String, dynamic> hall) {
    final rows = <MapEntry<String, String>>[
      MapEntry(
          'Full day',
          _num(hall, 'price') > 0 ? inr(_num(hall, 'price')) : 'On request'),
    ];
    const slabs = <MapEntry<String, String>>[
      MapEntry('Morning', 'morningPrice'),
      MapEntry('Afternoon', 'afternoonPrice'),
      MapEntry('Evening', 'eveningPrice'),
    ];
    for (final slab in slabs) {
      final value = hall[slab.value];
      if (value is num && value > 0) {
        rows.add(MapEntry(slab.key, inr(value)));
      }
    }
    return Card(
      margin: EdgeInsets.zero,
      child: Column(
        children: rows
            .map((row) => ListTile(
                  dense: true,
                  title: Text(row.key),
                  trailing: Text(row.value,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ))
            .toList(),
      ),
    );
  }

  Widget _planTile(Map<String, dynamic> plan) {
    final mode = _str(plan, 'mode', 'venue');
    const labels = <String, String>{
      'venue': 'Venue rental',
      'plate': 'Per plate',
      'combined': 'Plate + rental',
      'fixed': 'Fixed package',
    };
    final fixed = _num(plan, 'fixedPrice');
    final veg = _num(plan, 'vegRate');
    final maxGuests = _num(plan, 'maxGuests').round();
    String priceLine;
    if (mode == 'fixed' && fixed > 0) {
      priceLine = maxGuests > 0
          ? '${inr(fixed)} package · up to $maxGuests guests'
          : '${inr(fixed)} package';
    } else if (veg > 0) {
      priceLine = 'From ${inr(veg)} / plate (veg)';
    } else {
      priceLine = 'Custom rates';
    }
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: const Icon(Icons.receipt_long_outlined),
        title: Text(_str(plan, 'name', 'Pricing model'),
            style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text('${labels[mode] ?? mode} · $priceLine'),
      ),
    );
  }

  Widget _addonTile(Map<String, dynamic> addon) {
    final price = _num(addon, 'price');
    final unit = _str(addon, 'unit', 'event');
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: const Icon(Icons.add_circle_outline),
        title: Text(_str(addon, 'name', 'Service'),
            style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(_str(addon, 'category', 'Service')),
        trailing: Text(
          price > 0 ? '${inr(price)} / $unit' : 'On request',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

class HallEnquiryScreen extends StatefulWidget {
  const HallEnquiryScreen({
    super.key,
    required this.session,
    required this.hall,
  });

  final SessionStore session;
  final Map<String, dynamic> hall;

  @override
  State<HallEnquiryScreen> createState() => _HallEnquiryScreenState();
}

class _HallEnquiryScreenState extends State<HallEnquiryScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _name = TextEditingController();
  final TextEditingController _email = TextEditingController();
  final TextEditingController _message = TextEditingController();
  bool _consent = false;
  bool _busy = false;
  bool _sent = false;
  bool _loadingPolicy = true;
  String? _error;
  String? _policyId;
  int? _policyRevision;

  @override
  void initState() {
    super.initState();
    _message.text =
        'I am interested in ${_str(widget.hall, 'name', 'this hall')} and would '
        'like to know more about availability and pricing.';
    _loadPolicy();
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _message.dispose();
    super.dispose();
  }

  Future<void> _loadPolicy() async {
    try {
      final content =
          await widget.session.api.getList('/api/public/content?locale=en');
      Map<String, dynamic>? policy;
      for (final entry in content) {
        if (entry is Map<String, dynamic> &&
            entry['slug'] == 'privacy' &&
            entry['kind'] == 'page') {
          policy = entry;
          break;
        }
      }
      final revision = policy?['published_revision'];
      if (!mounted) return;
      setState(() {
        _policyId = policy?['id']?.toString();
        _policyRevision = revision is num ? revision.toInt() : null;
        _loadingPolicy = false;
      });
    } on ApiException {
      if (!mounted) return;
      setState(() => _loadingPolicy = false);
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_consent) {
      setState(() => _error = 'Please accept the privacy policy to continue.');
      return;
    }
    if (_policyId == null || _policyRevision == null) {
      setState(() => _error =
          'Enquiries are temporarily unavailable while the privacy policy is unpublished.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final hallName = _str(widget.hall, 'name', 'this hall');
    final city = _str(widget.hall, 'city');
    try {
      await widget.session.api.post('/api/public/enquiries', <String, dynamic>{
        'name': _name.text.trim(),
        'email': _email.text.trim(),
        'organization': _str(widget.hall, 'venue'),
        'message': 'Enquiry about $hallName${city.isEmpty ? '' : ' ($city)'}: '
            '${_message.text.trim()}',
        'locale': 'en',
        'consent': true,
        'website': '',
        'policyId': _policyId,
        'policyRevision': _policyRevision,
      });
      if (!mounted) return;
      setState(() {
        _busy = false;
        _sent = true;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Send an enquiry')),
      body: _sent
          ? EmptyState(
              icon: Icons.check_circle_outline,
              title: 'Enquiry sent!',
              message: 'Thanks — the venue team will get back to you about '
                  '${_str(widget.hall, 'name', 'your hall')} soon.',
              action: FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Done'),
              ),
            )
          : PageScaffold(
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _str(widget.hall, 'venue', 'Venue'),
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _str(widget.hall, 'name', 'Hall'),
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 16),
                    if (_error != null) ...[
                      ErrorBanner(message: _error!),
                      const SizedBox(height: 12),
                    ],
                    TextFormField(
                      controller: _name,
                      decoration: const InputDecoration(labelText: 'Your name'),
                      textInputAction: TextInputAction.next,
                      validator: (value) => (value == null ||
                              value.trim().length < 2)
                          ? 'Enter your name'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _email,
                      decoration:
                          const InputDecoration(labelText: 'Email address'),
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      validator: (value) {
                        final v = value?.trim() ?? '';
                        if (!v.contains('@') || v.length < 5) {
                          return 'Enter a valid email address';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _message,
                      decoration: const InputDecoration(
                        labelText: 'Message',
                        alignLabelWithHint: true,
                      ),
                      maxLines: 5,
                      maxLength: 3000,
                      validator: (value) =>
                          (value == null || value.trim().length < 10)
                              ? 'Tell the venue a little more (10+ characters)'
                              : null,
                    ),
                    CheckboxListTile(
                      value: _consent,
                      onChanged: (value) =>
                          setState(() => _consent = value ?? false),
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        'I agree to be contacted about this enquiry and accept '
                        'the privacy policy.',
                        style: TextStyle(fontSize: 13.5),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: (_busy || _loadingPolicy) ? null : _submit,
                        child: Text(_busy ? 'Sending…' : 'Send enquiry'),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
    );
  }
}

IconData _typeIconOf(Map<String, dynamic> hall) {
  final t = _str(hall, 'type').toLowerCase();
  if (t.contains('outdoor') || t.contains('garden')) return Icons.park_outlined;
  if (t.contains('rooftop') || t.contains('terrace')) {
    return Icons.roofing_outlined;
  }
  if (t.contains('banquet') || t.contains('indoor')) {
    return Icons.apartment_outlined;
  }
  return Icons.celebration_outlined;
}

String _str(Map<String, dynamic> map, String key, [String fallback = '']) {
  final value = map[key];
  if (value == null) return fallback;
  final text = value.toString().trim();
  return text.isEmpty ? fallback : text;
}

num _num(Map<String, dynamic> map, String key) {
  final value = map[key];
  if (value is num) return value;
  if (value is String) return num.tryParse(value) ?? 0;
  return 0;
}
