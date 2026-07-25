import 'dart:typed_data';

import 'package:lexical_collab/lexical_collab.dart';
import 'package:lexical_core/lexical_core.dart';
import 'package:lexical_rich_text/lexical_rich_text.dart';
import 'package:test/test.dart';

/// One participant: an editor, its replica, and the wire it talks on.
final class _Peer {
  _Peer(int clientId)
    : editor = LexicalEditor(nodes: richTextNodes),
      doc = CollabDoc(clientId: clientId) {
    collab = LexicalCollab(editor: editor, doc: doc);
    collab.updates.listen(outbox.add);
  }

  final LexicalEditor editor;
  final CollabDoc doc;
  late final LexicalCollab collab;
  final List<Uint8List> outbox = <Uint8List>[];

  String get text => editor.read(() => $getRoot().getTextContent());

  List<String> get types =>
      editor.read(() => $getRoot().children.map((node) => node.type).toList());

  void edit(void Function() fn) => editor.update(fn, discrete: true);
}

/// Delivers everything [from] has queued to [to].
Future<void> _deliver(_Peer from, _Peer to) async {
  await pumpEventQueue();
  final messages = [...from.outbox];
  from.outbox.clear();
  for (final message in messages) {
    to.collab.applyRemoteUpdate(message);
  }
  await pumpEventQueue();
}

/// Delivers in both directions until neither has anything to say.
Future<void> _settle(_Peer a, _Peer b) async {
  for (var round = 0; round < 4; round++) {
    await _deliver(a, b);
    await _deliver(b, a);
    if (a.outbox.isEmpty && b.outbox.isEmpty) return;
  }
}

/// Puts one paragraph of `text` into a fresh peer and starts sharing.
Future<_Peer> _host(String text) async {
  final peer = _Peer(1);
  peer.edit(() {
    $getRoot()
      ..clear()
      ..append($createParagraphNode()..append($createTextNode(text)));
  });
  peer.collab.start();
  await pumpEventQueue();
  return peer;
}

/// A second participant that joins [host]'s session.
Future<_Peer> _guest(_Peer host, [int clientId = 2]) async {
  final peer = _Peer(clientId);
  peer.collab.join(host.collab.encodeState());
  await pumpEventQueue();
  peer.outbox.clear();
  return peer;
}

void main() {
  group('joining', () {
    test('a guest sees what the host already wrote', () async {
      final host = await _host('hallo welt');
      final guest = await _guest(host);
      expect(guest.text, 'hallo welt');
      expect(guest.types, ['paragraph']);
    });

    test('joining replaces the guest\'s own empty document', () async {
      final host = await _host('inhalt');
      final guest = _Peer(2);
      guest.edit(() {
        $getRoot()
          ..clear()
          ..append($createParagraphNode());
      });
      guest.collab.join(host.collab.encodeState());
      await pumpEventQueue();

      // Not two paragraphs: the blank one the guest started with is gone.
      expect(guest.types, ['paragraph']);
      expect(guest.text, 'inhalt');
    });

    test('the whole document matches, field for field', () async {
      final host = _Peer(1);
      host.edit(() {
        $getRoot()
          ..clear()
          ..append(
            $createHeadingNode(HeadingTag.h2)..append($createTextNode('Titel')),
          )
          ..append(
            $createParagraphNode()
              ..append($createTextNode('normal '))
              ..append($createTextNode('fett')..setFormat(TextFormat.bold.bit)),
          )
          ..append($createQuoteNode()..append($createTextNode('Zitat')));
      });
      host.collab.start();
      await pumpEventQueue();

      final guest = await _guest(host);
      expect(
        jsonFirstDifference(host.editor.toJson(), guest.editor.toJson()),
        isNull,
      );
    });
  });

  group('typing', () {
    test('what one peer types appears at the other', () async {
      final host = await _host('hallo');
      final guest = await _guest(host);

      host.edit(() {
        final text = $getRoot().getFirstChild()! as ElementNode;
        (text.getFirstChild()! as TextNode).setTextContent('hallo welt');
      });
      await _deliver(host, guest);
      expect(guest.text, 'hallo welt');
    });

    test(
      'both typing at once keeps both, in the same order for each',
      () async {
        final host = await _host('mitte');
        final guest = await _guest(host);

        host.edit(() {
          final node =
              ($getRoot().getFirstChild()! as ElementNode).getFirstChild()!
                  as TextNode;
          node.setTextContent('${node.getTextContent()} rechts');
        });
        guest.edit(() {
          final node =
              ($getRoot().getFirstChild()! as ElementNode).getFirstChild()!
                  as TextNode;
          node.setTextContent('links ${node.getTextContent()}');
        });
        await _settle(host, guest);

        expect(host.text, guest.text);
        expect(host.text, contains('links'));
        expect(host.text, contains('rechts'));
        expect(host.text, contains('mitte'));
      },
    );

    test('a keystroke does not re-key the paragraph it lands in', () async {
      final host = await _host('erste');
      final guest = await _guest(host);
      final keyBefore = guest.editor.read(
        () => $getRoot().getFirstChild()!.key,
      );

      host.edit(() {
        final node =
            ($getRoot().getFirstChild()! as ElementNode).getFirstChild()!
                as TextNode;
        node.setTextContent('erster');
      });
      await _deliver(host, guest);

      // Reusing the node is what keeps the guest's caret, their selection and
      // their scroll position where they were.
      expect(
        guest.editor.read(() => $getRoot().getFirstChild()!.key),
        keyBefore,
      );
      expect(guest.text, 'erster');
    });
  });

  group('structure', () {
    test('a new block arrives as a block, not as text', () async {
      final host = await _host('eins');
      final guest = await _guest(host);

      host.edit(() {
        $getRoot().append(
          $createHeadingNode(HeadingTag.h3)..append($createTextNode('zwei')),
        );
      });
      await _deliver(host, guest);

      expect(guest.types, ['paragraph', 'heading']);
      expect(
        guest.editor.read(
          () => ($getRoot().getLastChild()! as HeadingNode).tag,
        ),
        HeadingTag.h3,
      );
    });

    test('a removed block is removed everywhere', () async {
      final host = await _host('eins');
      final guest = await _guest(host);
      host.edit(() => $getRoot().append($createParagraphNode()));
      await _deliver(host, guest);
      expect(guest.types.length, 2);

      host.edit(() => $getRoot().getLastChild()!.remove());
      await _deliver(host, guest);
      expect(guest.types.length, 1);
    });

    test('a formatting change travels as a property', () async {
      final host = await _host('text');
      final guest = await _guest(host);

      host.edit(() {
        final node =
            ($getRoot().getFirstChild()! as ElementNode).getFirstChild()!
                as TextNode;
        node.setFormat(TextFormat.bold.bit);
      });
      await _deliver(host, guest);

      expect(
        guest.editor.read(() {
          final node =
              ($getRoot().getFirstChild()! as ElementNode).getFirstChild()!
                  as TextNode;
          return node.getFormat();
        }),
        TextFormat.bold.bit,
      );
    });

    test('a block moved between parents keeps its content', () async {
      final host = await _host('start');
      final guest = await _guest(host);

      host.edit(() {
        $getRoot()
          ..append($createQuoteNode())
          ..append($createParagraphNode()..append($createTextNode('wandert')));
      });
      await _deliver(host, guest);

      host.edit(() {
        final quote = $getRoot().getChildAtIndex(1)! as ElementNode;
        final last = $getRoot().getLastChild()! as ElementNode;
        for (final child in last.children.toList()) {
          quote.append(child);
        }
        last.remove();
      });
      await _deliver(host, guest);

      expect(guest.types, ['paragraph', 'quote']);
      expect(
        guest.editor.read(() => $getRoot().getLastChild()!.getTextContent()),
        'wandert',
      );
    });
  });

  group('the local caret', () {
    test('text inserted ahead of it pushes it along', () async {
      final host = await _host('abcdef');
      final guest = await _guest(host);

      guest.edit(() {
        final node =
            ($getRoot().getFirstChild()! as ElementNode).getFirstChild()!
                as TextNode;
        node.select(4, 4);
      });
      guest.outbox.clear();

      host.edit(() {
        final node =
            ($getRoot().getFirstChild()! as ElementNode).getFirstChild()!
                as TextNode;
        node.setTextContent('XXabcdef');
      });
      await _deliver(host, guest);

      expect(guest.text, 'XXabcdef');
      // Still between 'd' and 'e', which is where the user put it.
      expect(
        guest.editor.read(
          () => ($getSelection()! as RangeSelection).focus.offset,
        ),
        6,
      );
    });

    test('text inserted behind it leaves it alone', () async {
      final host = await _host('abcdef');
      final guest = await _guest(host);

      guest.edit(() {
        final node =
            ($getRoot().getFirstChild()! as ElementNode).getFirstChild()!
                as TextNode;
        node.select(2, 2);
      });
      guest.outbox.clear();

      host.edit(() {
        final node =
            ($getRoot().getFirstChild()! as ElementNode).getFirstChild()!
                as TextNode;
        node.setTextContent('abcdefXX');
      });
      await _deliver(host, guest);
      expect(
        guest.editor.read(
          () => ($getSelection()! as RangeSelection).focus.offset,
        ),
        2,
      );
    });
  });

  group('commits', () {
    test('a remote change is tagged, so undo can leave it alone', () async {
      final host = await _host('eins');
      final guest = await _guest(host);
      final tags = <Set<String>>[];
      guest.editor.registerUpdateListener((update) => tags.add(update.tags));

      host.edit(() {
        final node =
            ($getRoot().getFirstChild()! as ElementNode).getFirstChild()!
                as TextNode;
        node.setTextContent('eins zwei');
      });
      await _deliver(host, guest);

      expect(tags, isNotEmpty);
      expect(tags.every((set) => set.contains(collaborationTag)), isTrue);
    });

    test('applying a remote change does not echo it back', () async {
      final host = await _host('eins');
      final guest = await _guest(host);

      host.edit(() {
        final node =
            ($getRoot().getFirstChild()! as ElementNode).getFirstChild()!
                as TextNode;
        node.setTextContent('eins zwei');
      });
      await _deliver(host, guest);
      // A commit made from a remote update must not become an update of its
      // own, or two peers keep each other awake forever.
      expect(guest.outbox, isEmpty);
    });
  });

  group('unknown node types', () {
    test('are kept in the document rather than dropped', () async {
      final host = await _host('bekannt');
      // A peer running a newer build sends a type this one has never heard
      // of. It cannot be rendered here, but it must survive.
      final foreign = host.doc.insertNode(host.doc.root, 1, 'sticker');
      host.doc.setProperty(foreign, 'emoji', '🎉');

      final guest = await _guest(host);
      expect(guest.types, ['paragraph']);
      expect(guest.doc.typeOf(foreign), 'sticker');
      expect(guest.doc.propsOf(foreign)['emoji'], '🎉');
    });
  });

  group('awareness', () {
    test('a peer\'s selection resolves into this editor\'s nodes', () async {
      final host = await _host('hallo welt');
      final guest = await _guest(host);

      host.edit(() {
        final node =
            ($getRoot().getFirstChild()! as ElementNode).getFirstChild()!
                as TextNode;
        node.select(2, 6);
      });
      host.collab.publishSelection();
      guest.collab.awareness.applyUpdate(host.collab.awareness.encodeUpdate());

      final selections = guest.collab.remoteSelections;
      expect(selections.keys, [host.doc.clientId]);
      final selection = selections.values.single;
      expect(selection.anchor.offset, 2);
      expect(selection.focus.offset, 6);
      // Resolved against the guest's own key for that node.
      expect(
        selection.anchor.key,
        guest.editor.read(
          () =>
              ($getRoot().getFirstChild()! as ElementNode).getFirstChild()!.key,
        ),
      );
      expect(selection.isCollapsed, isFalse);
    });

    test('presence expires when a peer goes quiet', () async {
      var now = DateTime.utc(2026);
      final awareness = Awareness(clientId: 1, clock: () => now);
      final peer = Awareness(clientId: 2, clock: () => now);
      peer.setLocalState({'name': 'Zwei'});
      awareness.applyUpdate(peer.encodeUpdate());
      expect(awareness.states.keys, contains(2));

      now = now.add(const Duration(seconds: 45));
      awareness.removeOutdated(const Duration(seconds: 30));
      // A peer that shut its laptop never says goodbye; its caret would sit
      // in the document forever.
      expect(awareness.states.keys, isNot(contains(2)));
    });

    test('an echo of our own state does not overwrite it', () {
      final mine = Awareness(clientId: 1)..setLocalState({'name': 'Eins'});
      final relayed = mine.encodeUpdate();
      mine.setLocalState({'name': 'Eins geändert'});
      mine.applyUpdate(relayed);
      expect(mine.localState, {'name': 'Eins geändert'});
    });
  });
}
