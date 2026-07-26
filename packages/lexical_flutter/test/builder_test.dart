import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexical_core/lexical_core.dart';
import 'package:lexical_flutter/lexical_flutter.dart';

void _write(LexicalEditor editor, String text) {
  editor.update(() {
    $getRoot()
      ..clear()
      ..append($createParagraphNode()..append($createTextNode(text)));
  }, discrete: true);
}

Future<void> _pump(WidgetTester tester, LexicalEditor editor) async {
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: LexicalBuilder(
        editor: editor,
        builder: (context, state, _) =>
            Text(editor.read(() => $getRoot().getTextContent())),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('it shows the committed document and follows it', (tester) async {
    final editor = LexicalEditor();
    _write(editor, 'erst');
    await _pump(tester, editor);
    expect(find.text('erst'), findsOneWidget);

    _write(editor, 'dann');
    await tester.pump();
    expect(find.text('dann'), findsOneWidget);
  });

  testWidgets('a commit during a build outside a frame does not throw', (
    tester,
  ) async {
    // The case a scheduler-phase check misses, and the first one an app runs
    // into: `runApp` builds the whole tree synchronously, outside any frame,
    // with the phase still `idle`. Registering behaviour or seeding an empty
    // document commits right there.
    //
    // It only surfaces when the builder sits *before* the committing widget
    // in build order — a toolbar above an editor. Below it the framework is
    // happy to visit a dirty descendant in the same pass, which is why this
    // went unnoticed until a bar was put on top. The build target below is a
    // sibling for exactly that reason: marking a widget outside the scope
    // being built is what the framework refuses.
    final editor = LexicalEditor();
    _write(editor, 'erst');
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Column(
          children: [
            LexicalBuilder(
              editor: editor,
              builder: (context, state, _) =>
                  Text(editor.read(() => $getRoot().getTextContent())),
            ),
            const SizedBox(key: ValueKey('sibling')),
          ],
        ),
      ),
    );
    await tester.pump();

    final sibling = tester.element(find.byKey(const ValueKey('sibling')));
    tester.binding.buildOwner!.buildScope(sibling, () {
      _write(editor, 'während des Builds');
    });
    // Two frames: the deferred rebuild is a post-frame callback, so it lands
    // at the end of the first one and is painted in the second.
    await tester.pump();
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('während des Builds'), findsOneWidget);
  });

  testWidgets('a commit during a frame does not throw either', (tester) async {
    final editor = LexicalEditor();
    _write(editor, 'erst');

    // A widget that commits from its own build, above the builder in the
    // tree — the toolbar-over-editor arrangement, at frame time.
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Column(
          children: [
            LexicalBuilder(
              editor: editor,
              builder: (context, state, _) =>
                  Text(editor.read(() => $getRoot().getTextContent())),
            ),
            _CommitsWhileBuilding(editor: editor),
          ],
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('aus einem Build'), findsOneWidget);
  });

  testWidgets('several commits in one frame are one rebuild', (tester) async {
    final editor = LexicalEditor();
    _write(editor, 'erst');
    var builds = 0;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: LexicalBuilder(
          editor: editor,
          builder: (context, state, _) {
            builds++;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    await tester.pump();
    final before = builds;

    final outside = tester.element(find.byType(Directionality));
    tester.binding.buildOwner!.buildScope(outside, () {
      _write(editor, 'a');
      _write(editor, 'b');
      _write(editor, 'c');
    });
    await tester.pump();
    await tester.pump();

    expect(builds - before, 1);
  });
}

/// Commits from inside its own `build`, which is exactly what registering
/// behaviour from `initState` amounts to.
class _CommitsWhileBuilding extends StatefulWidget {
  const _CommitsWhileBuilding({required this.editor});

  final LexicalEditor editor;

  @override
  State<_CommitsWhileBuilding> createState() => _CommitsWhileBuildingState();
}

class _CommitsWhileBuildingState extends State<_CommitsWhileBuilding> {
  @override
  void initState() {
    super.initState();
    _write(widget.editor, 'aus einem Build');
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
