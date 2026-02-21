// Tests widget de base pour l'application SchoolTrack Dashboard.
// Les tests spécifiques US 1.1 seront dans test/features/students/.

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_web_dashboard/main.dart';

void main() {
  testWidgets('Application démarre sans erreur', (WidgetTester tester) async {
    await tester.pumpWidget(const SchoolTrackDashboardApp());
    // Vérifie que l'app se construit sans exception
    expect(tester.takeException(), isNull);
  });
}
