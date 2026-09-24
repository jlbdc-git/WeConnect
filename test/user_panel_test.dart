import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:we_connect/core/models/profile.dart';
import 'package:we_connect/core/state/providers.dart';
import 'package:we_connect/features/home/user_panel.dart';

void main() {
  testWidgets('UserPanel shows the signed-in identity', (tester) async {
    final profile = const Profile(
      id: 'u1',
      username: 'jane_doe',
      displayName: 'Jane',
      tag: 4242,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          myProfileProvider.overrideWith((ref) async => profile),
        ],
        child: const MaterialApp(home: Scaffold(body: UserPanel())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Jane'), findsOneWidget);
    expect(find.text('@jane_doe'), findsOneWidget);
    expect(find.byIcon(Icons.settings_outlined), findsOneWidget);
  });

  testWidgets('tapping the panel opens the account menu with Log out',
      (tester) async {
    final profile = const Profile(
      id: 'u1',
      username: 'jane_doe',
      displayName: 'Jane',
      tag: 4242,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          myProfileProvider.overrideWith((ref) async => profile),
        ],
        child: const MaterialApp(home: Scaffold(body: UserPanel())),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Jane'));
    await tester.pumpAndSettle();

    // The menu exposes the two required destinations, plus the profile row.
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Log out'), findsOneWidget);
    expect(find.text('@jane_doe#4242'), findsOneWidget);
  });

  testWidgets('panel falls back to a question mark without a profile',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          myProfileProvider.overrideWith((ref) async => null),
        ],
        child: const MaterialApp(home: Scaffold(body: UserPanel())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Account'), findsOneWidget);
  });
}
