import 'package:flutter_test/flutter_test.dart';
import 'package:kira_void/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => isDesktop = false);

  testWidgets('phone mode starts with model download screen', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const KiraVoidApp());
    await tester.pumpAndSettle();
    expect(find.text('Нейросеть прямо на телефоне'), findsOneWidget);
    expect(find.text('Qwen 2.5 · 1.5B'), findsOneWidget);
    expect(find.text('Рисование прямо на телефоне', skipOffstage: false), findsOneWidget);
  });

  testWidgets('linux desktop uses the local server', (tester) async {
    isDesktop = true;
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const KiraVoidApp());
    await tester.pumpAndSettle();
    expect(find.text('Спроси что угодно'), findsOneWidget);
    expect(find.text('На телефоне', skipOffstage: false), findsNothing);
  });

  testWidgets('pc mode without server opens settings', (tester) async {
    SharedPreferences.setMockInitialValues({'onPhone': false});
    await tester.pumpWidget(const KiraVoidApp());
    await tester.pumpAndSettle();
    expect(find.text('Адрес сервера'), findsOneWidget);
  });
}
