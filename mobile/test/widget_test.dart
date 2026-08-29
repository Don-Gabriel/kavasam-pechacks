import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kavasam_mobile/main.dart';

void main() {
  testWidgets('shows the offline caller ID dialer', (tester) async {
    await tester.pumpWidget(const KavasamApp());
    await tester.pumpAndSettle();

    expect(find.text('KAVASAM'), findsOneWidget);
    expect(find.text('OFFLINE'), findsOneWidget);
    expect(find.text('Make Kavasam my phone app'), findsOneWidget);
    expect(find.text('Dial'), findsOneWidget);
    expect(find.text('Recents'), findsOneWidget);
    expect(find.text('Contacts'), findsOneWidget);
    expect(find.text('Safety'), findsOneWidget);
    expect(find.text('Guardian'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('dial pad enters a number', (tester) async {
    await tester.pumpWidget(const KavasamApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('1'));
    await tester.tap(find.text('2'));
    await tester.tap(find.text('3'));
    await tester.pump();

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller?.text, '123');
  });
}
