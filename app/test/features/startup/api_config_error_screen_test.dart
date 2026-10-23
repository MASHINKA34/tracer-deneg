import 'package:flutter_test/flutter_test.dart';
import 'package:milionchik/features/startup/api_config_error_app.dart';

void main() {
  testWidgets('нет адреса сервера - заголовок и подсказка из ARB и причина', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ApiConfigErrorApp(details: 'API_URL is not set: reason-marker'),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ApiConfigErrorScreen), findsOneWidget);
    expect(find.text('Не задан адрес сервера'), findsOneWidget);
    expect(
      find.textContaining('--dart-define=API_URL=https://<домен>/api/v1'),
      findsOneWidget,
    );
    expect(find.text('API_URL is not set: reason-marker'), findsOneWidget);
  });
}
