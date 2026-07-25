// Run it with:  dart run example/main.dart
//
// Two editors, no server, no network — just bytes handed from one to the
// other. That is the whole model: a peer produces updates, a peer applies
// them, and any two peers that have seen the same updates hold the same
// document. A relay is a convenience, not a source of truth.
import 'dart:typed_data';

import 'package:lexical_collab/lexical_collab.dart';
import 'package:lexical_core/lexical_core.dart';

/// One participant, with an outbox standing in for a socket.
final class Peer {
  Peer(this.name, int clientId)
    : editor = LexicalEditor(),
      doc = CollabDoc(clientId: clientId) {
    registerRichText(editor);
    collab = LexicalCollab(editor: editor, doc: doc);
    collab.updates.listen(outbox.add);
  }

  final String name;
  final LexicalEditor editor;
  final CollabDoc doc;
  late final LexicalCollab collab;
  final List<Uint8List> outbox = <Uint8List>[];

  String get text => editor.read(() => $getRoot().getTextContent());

  /// Types [text] at [offset] of the first paragraph, as a person would.
  void type(String text, int offset) {
    editor.update(() {
      final node =
          ($getRoot().getFirstChild()! as ElementNode).getFirstChild()!
              as TextNode;
      node.select(offset, offset);
      ($getSelection()! as RangeSelection).insertText(text);
    }, discrete: true);
  }
}

/// Delivers everything [from] has queued to [to].
Future<void> deliver(Peer from, Peer to) async {
  await Future<void>.delayed(Duration.zero);
  for (final message in [...from.outbox]) {
    to.collab.applyRemoteUpdate(message);
  }
  from.outbox.clear();
}

Future<void> main() async {
  final ada = Peer('Ada', 1);
  ada.editor.update(() {
    $getRoot()
      ..clear()
      ..append($createParagraphNode()..append($createTextNode('Hallo Welt')));
  }, discrete: true);
  ada.collab.start();
  await Future<void>.delayed(Duration.zero);

  // Grace joins with the session's state before starting, which is what keeps
  // her own empty starting paragraph out of the room.
  final grace = Peer('Grace', 2);
  grace.collab.join(ada.collab.encodeState());
  await Future<void>.delayed(Duration.zero);
  grace.outbox.clear();
  print('Grace joined and sees: "${grace.text}"');

  // Both type at once, in the same paragraph, without hearing from each other.
  ada.type('schöne ', 6);
  grace.type('Sag ', 0);
  print('\nbefore syncing');
  print('  Ada:   "${ada.text}"');
  print('  Grace: "${grace.text}"');

  await deliver(ada, grace);
  await deliver(grace, ada);
  print('\nafter syncing — both edits kept, in one order both agree on');
  print('  Ada:   "${ada.text}"');
  print('  Grace: "${grace.text}"');
  print('  identical: ${ada.text == grace.text}');

  // Structure merges too, and a peer's node keys are never involved: they are
  // ephemeral, so the document carries stable ids of its own instead.
  ada.editor.update(() {
    $getRoot().append(
      $createParagraphNode()..append($createTextNode('Ein zweiter Absatz.')),
    );
  }, discrete: true);
  await deliver(ada, grace);
  print(
    '\nGrace now has ${grace.editor.read(() => $getRoot().childrenSize)} '
    'blocks: "${grace.text.replaceAll('\n', ' ⏎ ')}"',
  );

  // Presence rides beside the document rather than inside it: a caret is
  // worth nothing an hour later, and the document would never forget it.
  ada.collab.awareness.setLocalField('name', 'Ada');
  ada.collab.publishSelection();
  grace.collab.awareness.applyUpdate(ada.collab.awareness.encodeUpdate());

  final carets = grace.collab.remoteSelections;
  for (final entry in carets.entries) {
    final who = grace.collab.awareness.states[entry.key]?.state['name'];
    print(
      '\nGrace can see $who\'s caret at offset '
      '${entry.value.focus.offset} of node ${entry.value.focus.key}',
    );
  }

  // A message is idempotent and order-independent: replaying it changes
  // nothing, and one that arrives early is held until it can be applied.
  final replay = ada.collab.encodeState();
  grace.collab.applyRemoteUpdate(replay);
  print('after replaying the whole state: "${grace.text == ada.text}"');
}
