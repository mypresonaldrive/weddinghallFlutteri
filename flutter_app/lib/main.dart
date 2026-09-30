import 'dart:async';

import 'package:flutter/material.dart';

import 'src/app.dart';
import 'src/core/appearance.dart';
import 'src/core/session.dart';
import 'src/core/storage.dart';
import 'src/core/store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await KeyValueStore.open();
  final session = SessionStore(prefs);
  final appearance = AppearanceStore(prefs);
  final workspace = WorkspaceStore(session);
  await appearance.load();
  unawaited(session.init());
  runApp(GatherhallApp(
    session: session,
    workspace: workspace,
    appearance: appearance,
    prefs: prefs,
  ));
}
