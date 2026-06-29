// This is a basic Flutter widget test.
// Updated to match DarkDownloaderApp naming.

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dark_downloader/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    // We wrap it in ProviderScope because the app uses Riverpod.
    await tester.pumpWidget(
      const ProviderScope(
        child: DarkDownloaderApp(),
      ),
    );

    // Verify that the app starts (Check for a basic element instead of a counter)
    // Since it's a downloader app, we just check if it renders without crashing.
    expect(find.byType(DarkDownloaderApp), findsOneWidget);
  });
}
