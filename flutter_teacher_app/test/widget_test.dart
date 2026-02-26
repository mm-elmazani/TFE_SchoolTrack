import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_teacher_app/main.dart';

void main() {
  testWidgets('SchoolTrackApp smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const SchoolTrackApp());
    expect(find.byType(SchoolTrackApp), findsOneWidget);
  });
}
