import 'package:flutter_test/flutter_test.dart';
import 'package:lexical_editor_flutter_example/main.dart';

void main() {
  testWidgets('the example mounts and renders its document as markdown', (
    tester,
  ) async {
    await tester.pumpWidget(const ExampleApp());
    await tester.pump();
    expect(find.text('lexical_editor_flutter'), findsOneWidget);
    // The inspector shows the same document the editor holds.
    expect(find.textContaining('# Lexical, auf Flutter'), findsOneWidget);
  });
}
