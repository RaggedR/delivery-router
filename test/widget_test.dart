import 'package:flutter_test/flutter_test.dart';
import 'package:delivery_router/main.dart';

void main() {
  testWidgets('App renders home screen', (WidgetTester tester) async {
    await tester.pumpWidget(const DeliveryRouterApp());
    expect(find.text('Delivery Router'), findsOneWidget);
  });
}
