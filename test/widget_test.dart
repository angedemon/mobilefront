
import 'package:flutter_test/flutter_test.dart';

import 'package:yele/main.dart';

void main() {
  testWidgets('YeleApp se construit sans erreur', (WidgetTester tester) async {
    await tester.pumpWidget(const YeleApp());
    await tester.pump();

    // L'app démarre sur l'écran « Test complet ».
    expect(find.text('Test complet'), findsWidgets);
  });

  testWidgets("Sans consentement, l'app s'ouvre sur l'écran d'accord",
      (WidgetTester tester) async {
    await tester.pumpWidget(const YeleApp(hasConsented: false));
    await tester.pump();

    expect(find.text('Avant de commencer'), findsOneWidget);
    expect(find.text("J'accepte et je continue"), findsOneWidget);
    expect(find.text('Test complet'), findsNothing);
  });
}
