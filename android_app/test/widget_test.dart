import 'package:flutter_test/flutter_test.dart';
import 'package:kira_void/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('opens settings on first launch', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const KiraVoidApp());
    await tester.pumpAndSettle();
    expect(find.text('Адрес сервера'), findsOneWidget);
  });
}
