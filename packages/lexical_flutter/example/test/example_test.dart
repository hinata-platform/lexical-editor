import 'package:flutter_test/flutter_test.dart';
import 'package:lexical_flutter_example/main.dart';

void main() {
  testWidgets('the example mounts and shows its document', (tester) async {
    await tester.pumpWidget(const ExampleApp());
    await tester.pump();
    expect(find.text('lexical_flutter'), findsOneWidget);
    expect(find.textContaining('blocks: 2'), findsOneWidget);
  });
}
