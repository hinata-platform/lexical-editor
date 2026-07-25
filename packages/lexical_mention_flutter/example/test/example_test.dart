import 'package:flutter_test/flutter_test.dart';
import 'package:lexical_mention_flutter_example/main.dart';

void main() {
  testWidgets('the example mounts with the typeahead wired up', (tester) async {
    await tester.pumpWidget(const ExampleApp());
    await tester.pump();
    expect(find.text('lexical_mention_flutter'), findsOneWidget);
  });
}
