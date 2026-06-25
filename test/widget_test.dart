import 'package:flutter_test/flutter_test.dart';
import 'package:inferno_storm1/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const InfernoStormApp());
    expect(find.byType(InfernoStormApp), findsOneWidget);
  });
}
