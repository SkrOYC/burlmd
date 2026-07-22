import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('App renders main scaffold', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Text('burlmd'))),
    );
    expect(find.text('burlmd'), findsOneWidget);
  });
}
