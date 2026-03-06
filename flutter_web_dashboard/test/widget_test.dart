// Tests widget de base pour l'application SchoolTrack Dashboard.

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_web_dashboard/features/auth/providers/auth_provider.dart';
import 'package:flutter_web_dashboard/main.dart';

void main() {
  testWidgets('Application demarre sans erreur', (WidgetTester tester) async {
    final authProvider = AuthProvider();
    await tester.pumpWidget(SchoolTrackDashboardApp(authProvider: authProvider));
    // Verifie que l'app se construit sans exception
    expect(tester.takeException(), isNull);
  });
}
