import 'package:flutter_test/flutter_test.dart';
import 'package:lexical_mention/lexical_mention.dart';
import 'package:lexical_mention_flutter/lexical_mention_flutter.dart';
import 'package:lexical_mention_flutter_example/main.dart';

void main() {
  testWidgets('the example mounts with the typeahead wired up', (tester) async {
    await tester.pumpWidget(const ExampleApp());
    await tester.pump();
    expect(find.text('lexical_mention_flutter'), findsOneWidget);

    // The chips render, which is more than cosmetic: a token builder runs
    // inside the editor's read, but the widget it returns is built later with
    // no editor state around it. A chip that kept the node instead of its
    // values throws on the first frame, and this is what catches it.
    expect(find.text('@Ada Lovelace'), findsOneWidget);
    expect(find.text('#108'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping a mention routes to what it points at', (tester) async {
    await tester.pumpWidget(const ExampleApp());
    await tester.pump();

    await tester.tap(find.text('#108'));
    // Inside an editable a single tap resolves only after the double-tap
    // deadline, because double-tap-to-select shares the gesture arena.
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    expect(find.text('navigate → /issues/108'), findsOneWidget);
  });

  test('an inserted mention carries its trigger exactly once', () async {
    // The label builder prepends the trigger, so a suggestion label that
    // already begins with one produces `##108`. It reads on screen as a
    // rendering bug and is really a data bug, which is why it is pinned here.
    const trigger = MentionTrigger(character: '#', mentionType: 'issue');
    final suggestions = await searchDemoDirectory(
      const MentionQuery(text: '108', mentionType: 'issue'),
    );
    expect(suggestions, isNotEmpty);
    expect(defaultMentionLabel(trigger, suggestions.first), '#108');
  });
}
