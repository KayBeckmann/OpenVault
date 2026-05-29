import 'package:flutter_test/flutter_test.dart';
import 'package:app/main.dart';

void main() {
  testWidgets('OpenVault app smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const OpenVaultApp());
    await tester.pumpAndSettle();
    expect(find.text('OpenVault'), findsWidgets);
  });
}
