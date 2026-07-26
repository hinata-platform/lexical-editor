// Run it with:  dart run example/main.dart
//
// The document model on its own — no Flutter, no rendering, no widgets. This
// is the whole point of the package: an editor's state is a data structure,
// and a data structure can be built, edited, serialized and tested without a
// screen anywhere near it.
import 'package:lexical_core/lexical_core.dart';

void main() {
  final editor = LexicalEditor();
  registerRichText(editor);

  // 1. Build a document ------------------------------------------------
  editor.update(() {
    $getRoot()
      ..clear()
      ..append(
        $createParagraphNode()
          ..append($createTextNode('Hello '))
          ..append($createTextNode('world')..setFormat(TextFormat.bold.bit)),
      );
  }, discrete: true);

  print('text:      ${editor.read(() => $getRoot().getTextContent())}');

  // 2. Edit it through the selection ------------------------------------
  // Every edit goes through a selection, exactly as a keystroke would.
  editor.update(() {
    final text =
        ($getRoot().getFirstChild()! as ElementNode).getFirstChild()!
            as TextNode;
    text.select(6, 6);
    ($getSelection()! as RangeSelection).insertText('lovely ');
  }, discrete: true);

  print('after typing: ${editor.read(() => $getRoot().getTextContent())}');

  // Enter splits the block at the caret. `insertParagraph` is what the
  // command does; putting the caret at the very end first is what makes it
  // *add* a paragraph rather than tear this one in half.
  editor.update(() {
    final paragraph = $getRoot().getLastChild()! as ElementNode;
    (paragraph.getLastChild()! as TextNode).selectEnd();
    ($getSelection()! as RangeSelection)
      ..insertParagraph()
      ..insertText('A second paragraph');
  }, discrete: true);

  print('blocks:    ${editor.read(() => $getRoot().childrenSize)}');

  // 3. Serialize ---------------------------------------------------------
  // This JSON is Lexical's own wire format: paste it into lexical.dev and it
  // opens. That compatibility is the reason the model is a port rather than
  // an invention.
  final json = editor.toJson();
  print('\nJSON:\n${editor.toJsonString()}\n');

  // 4. Round-trip --------------------------------------------------------
  // The contract is a *fixed point*: encoding a decoded document returns the
  // same document. Not byte-equality against hand-written input — Lexical
  // normalizes on import, and so does this.
  final reopened = editor.parseEditorState(json);
  print('round-trips: ${jsonFirstDifference(json, reopened.toJson()) == null}');

  // 5. Listen ------------------------------------------------------------
  editor.registerUpdateListener((update) {
    print('commit:    ${update.dirtyLeaves.length} leaf/leaves changed');
  });
  editor.update(() {
    ($getRoot().getLastChild()! as ElementNode).append(
      $createTextNode(' — appended'),
    );
  }, discrete: true);

  print('final:     ${editor.read(() => $getRoot().getTextContent())}');
}
