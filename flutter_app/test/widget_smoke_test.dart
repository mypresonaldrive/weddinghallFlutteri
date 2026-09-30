import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gatherhall/src/core/appearance.dart';
import 'package:gatherhall/src/core/storage.dart';
import 'package:gatherhall/src/widgets/common.dart';

AppearanceStore newAppearance() => AppearanceStore(
    KeyValueStore(File('${Directory.systemTemp.path}/smoke_state.json')));

void main() {
  testWidgets('light theme renders the shared widgets', (tester) async {
    final appearance = newAppearance();
    await tester.pumpWidget(MaterialApp(
      theme: appearance.light(),
      darkTheme: appearance.dark(),
      home: const Scaffold(
        body: PageScaffold(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              StatusChip(label: 'Confirmed', tone: 'green'),
              SizedBox(height: 8),
              StatTile(
                label: 'Revenue',
                value: '₹1,85,000',
                icon: Icons.payments_outlined,
                caption: 'this month',
              ),
              SizedBox(height: 8),
              ErrorBanner(message: 'Something went wrong'),
              SizedBox(height: 8),
              SectionHeader(title: 'Halls'),
              SizedBox(height: 8),
              LoadingCenter(label: 'Loading…'),
            ],
          ),
        ),
      ),
    ));

    expect(find.text('Confirmed'), findsOneWidget);
    expect(find.text('₹1,85,000'), findsOneWidget);
    expect(find.text('Something went wrong'), findsOneWidget);
    expect(find.text('Halls'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dark theme renders without exceptions', (tester) async {
    final appearance = newAppearance();
    await tester.pumpWidget(MaterialApp(
      theme: appearance.light(),
      darkTheme: appearance.dark(),
      themeMode: ThemeMode.dark,
      home: const Scaffold(
        body: EmptyState(
          icon: Icons.search_off,
          title: 'Nothing here',
          message: 'No records match this filter.',
        ),
      ),
    ));
    expect(find.text('Nothing here'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('confirm dialog returns the chosen value', (tester) async {
    bool? result;
    await tester.pumpWidget(MaterialApp(
      theme: newAppearance().light(),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                result = await confirmDialog(
                  context,
                  title: 'Delete booking',
                  message: 'This cannot be undone.',
                  confirmLabel: 'Delete',
                );
              },
              child: const Text('Go'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('Go'));
    await tester.pumpAndSettle();
    expect(find.text('Delete booking'), findsOneWidget);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(result, isTrue);
  });
}
