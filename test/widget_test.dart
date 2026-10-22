import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:trailmate/app.dart';

void main() {
  testWidgets('应用可正常启动', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: TrailMateApp()));
    expect(find.text('我的旅程'), findsOneWidget);
  });
}
