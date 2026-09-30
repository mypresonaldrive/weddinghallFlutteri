import 'package:flutter/material.dart';

import 'core/appearance.dart';
import 'core/session.dart';
import 'core/storage.dart';
import 'core/store.dart';
import 'screens/auth.dart';
import 'screens/intro.dart';
import 'screens/shell.dart';

class GatherhallApp extends StatelessWidget {
  const GatherhallApp({
    super.key,
    required this.session,
    required this.workspace,
    required this.appearance,
    required this.prefs,
  });

  final SessionStore session;
  final WorkspaceStore workspace;
  final AppearanceStore appearance;
  final KeyValueStore prefs;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appearance,
      builder: (context, _) => MaterialApp(
        title: 'Gatherhall',
        debugShowCheckedModeBanner: false,
        themeMode: appearance.mode,
        theme: appearance.light(),
        darkTheme: appearance.dark(),
        home: RootGate(
          session: session,
          workspace: workspace,
          appearance: appearance,
          prefs: prefs,
        ),
      ),
    );
  }
}

class RootGate extends StatefulWidget {
  const RootGate({
    super.key,
    required this.session,
    required this.workspace,
    required this.appearance,
    required this.prefs,
  });

  final SessionStore session;
  final WorkspaceStore workspace;
  final AppearanceStore appearance;
  final KeyValueStore prefs;

  @override
  State<RootGate> createState() => _RootGateState();
}

class _RootGateState extends State<RootGate> {
  late bool _introSeen = widget.prefs.get('intro_seen') == true;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge(
          <Listenable>[widget.session, widget.workspace]),
      builder: (context, _) {
        switch (widget.session.phase) {
          case BootPhase.starting:
            return const SplashScreen();
          case BootPhase.unreachable:
            return UnreachableScreen(session: widget.session);
          case BootPhase.signedOut:
            if (!_introSeen) {
              return IntroCarousel(
                prefs: widget.prefs,
                session: widget.session,
                onDone: () => setState(() => _introSeen = true),
              );
            }
            return AuthScreen(
                session: widget.session, workspace: widget.workspace);
          case BootPhase.needsOnboarding:
            return OnboardingScreen(session: widget.session);
          case BootPhase.workspace:
            return WorkspaceShell(
                session: widget.session,
                workspace: widget.workspace,
                appearance: widget.appearance);
        }
      },
    );
  }
}

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.local_florist, size: 40, color: scheme.onPrimaryContainer),
            ),
            const SizedBox(height: 18),
            Text('Gatherhall',
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 18),
            const SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
          ],
        ),
      ),
    );
  }
}

class UnreachableScreen extends StatelessWidget {
  const UnreachableScreen({super.key, required this.session});

  final SessionStore session;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_off, size: 46, color: Color(0xFF9A6700)),
                const SizedBox(height: 14),
                Text('Cannot reach the server',
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Text(
                  session.bootError ??
                      'Start the Gatherhall server, then retry. You can also change the server address.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 8),
                Text('Server: ${session.baseUrl}',
                    style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    OutlinedButton(
                      onPressed: () => _changeServer(context),
                      child: const Text('Change server'),
                    ),
                    const SizedBox(width: 12),
                    FilledButton(
                      onPressed: () => session.checkServer(),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _changeServer(BuildContext context) async {
    final controller = TextEditingController(text: session.baseUrl);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Server address'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: inputDecorationLite('https://venues.example.com'),
          onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
              child: const Text('Save')),
        ],
      ),
    );
    if (result != null && result.isNotEmpty) {
      await session.setBaseUrl(result);
    }
  }
}

InputDecoration inputDecorationLite(String hint) => InputDecoration(hintText: hint);
