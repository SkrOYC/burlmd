import 'package:burlmd/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('App renders main scaffold', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());
    expect(find.text('burlmd'), findsWidgets);
  });
}
