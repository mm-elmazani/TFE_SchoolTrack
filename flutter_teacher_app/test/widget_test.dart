import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_teacher_app/core/database/local_db.dart';
import 'package:flutter_teacher_app/main.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() {
    LocalDb.testDatabasePath = inMemoryDatabasePath;
  });

  tearDown(() async {
    await LocalDb.instance.closeForTest();
  });

  testWidgets('SchoolTrackApp smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const SchoolTrackApp());
    expect(find.byType(SchoolTrackApp), findsOneWidget);
  });
}
