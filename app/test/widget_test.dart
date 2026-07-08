import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/main.dart';

void main() {
  testWidgets('OpenVault app boots without error', (WidgetTester tester) async {
    await tester.pumpWidget(const OpenVaultApp());
    // One frame only — the real app has async startup (session restore, vault
    // loading, spinners), so pumpAndSettle would never settle.
    await tester.pump();
    expect(find.byType(MaterialApp), findsWidgets);
  });
}
