import 'package:flutter/material.dart';

import '../core/appearance.dart';
import '../core/models.dart';
import '../core/session.dart';
import '../core/store.dart';
import 'billing.dart';
import 'calendar.dart';
import 'catalog.dart';
import 'clients.dart';
import 'dashboard.dart';
import 'halls.dart';
import 'payments.dart';
import 'platform_console.dart';
import 'reports.dart';
import 'settings.dart';
import 'staff.dart';
import 'bookings.dart';

class WorkspaceShell extends StatefulWidget {
  const WorkspaceShell({
    super.key,
    required this.session,
    required this.workspace,
    required this.appearance,
  });

  final SessionStore session;
  final WorkspaceStore workspace;
  final AppearanceStore appearance;

  @override
  State<WorkspaceShell> createState() => _WorkspaceShellState();
}

class _Section {
  const _Section(this.id, this.label, this.icon, this.builder);
  final String id;
  final String label;
  final IconData icon;
  final Widget Function() builder;
}

class _WorkspaceShellState extends State<WorkspaceShell> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.workspace.halls.isEmpty && !widget.workspace.loading) {
        widget.workspace.load();
      }
    });
  }

  List<_Section> _sections() {
    final user = widget.session.user;
    final role = user?.role;
    final sections = <_Section>[
      if (role != 'client')
        _Section('dashboard', 'Dashboard', Icons.dashboard_outlined,
            () => DashboardScreen(session: widget.session, workspace: widget.workspace)),
      _Section('bookings', role == 'client' ? 'My bookings' : 'Bookings',
          Icons.event_note_outlined,
          () => BookingsScreen(session: widget.session, workspace: widget.workspace)),
      if (role != 'client')
        _Section('calendar', 'Calendar', Icons.calendar_month_outlined,
            () => CalendarScreen(session: widget.session, workspace: widget.workspace)),
      if (role != 'client')
        _Section('halls', 'Halls', Icons.warehouse_outlined,
            () => HallsScreen(session: widget.session, workspace: widget.workspace)),
      if (role != 'client')
        _Section('clients', 'Clients', Icons.people_outline,
            () => ClientsScreen(session: widget.session, workspace: widget.workspace)),
      _Section('payments', 'Payments', Icons.payments_outlined,
          () => PaymentsScreen(session: widget.session, workspace: widget.workspace)),
      if (role == 'owner') ...[
        _Section('plans', 'Pricing models', Icons.local_dining_outlined,
            () => CatalogScreen(session: widget.session, workspace: widget.workspace, kind: 'plans')),
        _Section('addons', 'Services', Icons.add_business_outlined,
            () => CatalogScreen(session: widget.session, workspace: widget.workspace, kind: 'addons')),
        _Section('team', 'Team', Icons.groups_2_outlined,
            () => StaffScreen(session: widget.session, workspace: widget.workspace)),
        _Section('reports', 'Reports', Icons.insights_outlined,
            () => ReportsScreen(workspace: widget.workspace)),
        if (widget.session.config.isSaas && user?.isOwner == true)
          _Section('billing', 'Billing', Icons.workspace_premium_outlined,
              () => BillingScreen(session: widget.session, workspace: widget.workspace)),
      ],
      if (widget.session.config.isSaas && user?.platformAdmin == true)
        _Section('platform', 'Platform console', Icons.admin_panel_settings_outlined,
            () => PlatformConsole(session: widget.session, workspace: widget.workspace)),
      _Section('settings', 'Settings', Icons.settings_outlined,
          () => SettingsScreen(
              session: widget.session,
              workspace: widget.workspace,
              appearance: widget.appearance)),
    ];
    return sections;
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final user = session.user;
    final sections = _sections();
    if (_index >= sections.length) _index = 0;
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= 1000;
    final scheme = Theme.of(context).colorScheme;
    final section = sections[_index];

    final body = ListenableBuilder(
      listenable: widget.workspace,
      builder: (context, _) {
        final content = IndexedStack(
          index: _index,
          children: [for (final s in sections) s.builder()],
        );
        final inactive = session.config.isSaas &&
            user?.inWorkspace == true &&
            user?.entitlementActive == false;
        if (!inactive) return content;
        return Column(
          children: [
            Container(
              width: double.infinity,
              color: const Color(0xFFFFF4E5),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: const Text(
                'Your subscription is inactive. Records are read-only until the plan is renewed from Billing.',
                style: TextStyle(color: Color(0xFF7A4D00), fontWeight: FontWeight.w600),
              ),
            ),
            Expanded(child: content),
          ],
        );
      },
    );

    final leading = wide
        ? null
        : Builder(
            builder: (ctx) => IconButton(
              tooltip: 'Menu',
              icon: const Icon(Icons.menu),
              onPressed: () => Scaffold.of(ctx).openDrawer(),
            ),
          );

    final appBar = AppBar(
      leading: leading,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(section.label, overflow: TextOverflow.ellipsis),
          if (user != null)
            Text(
              [
                if (user.tenant.isNotEmpty) user.tenant,
                if (user.role != null) user.role!.toUpperCase(),
              ].join(' · '),
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
              overflow: TextOverflow.ellipsis,
            ),
        ],
      ),
      actions: [
        IconButton(
          tooltip: 'Refresh data',
          onPressed: () => widget.workspace.load(),
          icon: const Icon(Icons.refresh),
        ),
        if (user != null) _accountMenu(user),
        const SizedBox(width: 8),
      ],
    );

    if (wide) {
      return Scaffold(
        appBar: appBar,
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: _index,
              extended: width >= 1280,
              onDestinationSelected: (i) => setState(() => _index = i),
              labelType: width >= 1280
                  ? NavigationRailLabelType.none
                  : NavigationRailLabelType.all,
              leading: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: CircleAvatar(
                  backgroundColor: scheme.primaryContainer,
                  child: Text(
                    user?.initials ?? '?',
                    style: TextStyle(
                        color: scheme.onPrimaryContainer, fontWeight: FontWeight.w800),
                  ),
                ),
              ),
              destinations: [
                for (final s in sections)
                  NavigationRailDestination(
                    icon: Icon(s.icon),
                    selectedIcon: Icon(s.icon),
                    label: Text(s.label),
                  ),
              ],
            ),
            VerticalDivider(width: 1, color: scheme.outlineVariant),
            Expanded(child: body),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: appBar,
      drawer: Drawer(
        child: SafeArea(
          child: Column(
            children: [
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: scheme.primaryContainer,
                  child: Text(
                    user?.initials ?? '?',
                    style: TextStyle(
                        color: scheme.onPrimaryContainer, fontWeight: FontWeight.w800),
                  ),
                ),
                title: Text(user?.name ?? '',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(user?.tenant ?? user?.email ?? '',
                    overflow: TextOverflow.ellipsis),
              ),
              const Divider(),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  children: [
                    for (var i = 0; i < sections.length; i++)
                      ListTile(
                        leading: Icon(sections[i].icon),
                        title: Text(sections[i].label),
                        selected: i == _index,
                        selectedTileColor:
                            Theme.of(context).colorScheme.primaryContainer.withAlpha(90),
                        onTap: () {
                          setState(() => _index = i);
                          Navigator.of(context).pop();
                        },
                      ),
                  ],
                ),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.logout),
                title: const Text('Sign out'),
                onTap: () => widget.session.logout(),
              ),
            ],
          ),
        ),
      ),
      body: body,
    );
  }

  Widget _accountMenu(CurrentUser user) {
    return PopupMenuButton<String>(
      tooltip: 'Account',
      onSelected: (value) async {
        switch (value) {
          case 'settings':
            setState(() => _index = _sections().indexWhere((s) => s.id == 'settings'));
            break;
          case 'logout':
            await widget.session.logout();
            break;
        }
      },
      itemBuilder: (ctx) => [
        PopupMenuItem(
          enabled: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(user.name, style: const TextStyle(fontWeight: FontWeight.w700)),
              Text(user.email, style: Theme.of(ctx).textTheme.bodySmall),
            ],
          ),
        ),
        const PopupMenuItem(value: 'settings', child: Text('Profile & settings')),
        const PopupMenuItem(value: 'logout', child: Text('Sign out')),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: CircleAvatar(
          radius: 16,
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          child: Text(user.initials,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: Theme.of(context).colorScheme.onPrimaryContainer)),
        ),
      ),
    );
  }
}
