import 'package:burlmd/main.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('App renders main scaffold', (WidgetTester tester) async {
    // `MyApp` reads `authControllerProvider` (SYNC-C002's login gate), so it
    // now needs a `ProviderScope` ancestor the way every other
    // Riverpod-backed widget in this app does.
    await tester.pumpWidget(const ProviderScope(child: MyApp()));
    expect(find.text('burlmd'), findsWidgets);
  });
}
