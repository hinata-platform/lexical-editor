import 'dart:typed_data';

import 'package:lexical_collab/lexical_collab.dart';
import 'package:test/test.dart';

/// Sends everything [from] holds that [to] is missing.
void _sync(CollabDoc from, CollabDoc to) {
  to.applyUpdate(from.encodeStateAsUpdate(to.encodeStateVector()));
}

/// Sends in both directions, which is what convergence means.
void _syncBoth(CollabDoc a, CollabDoc b) {
  _sync(a, b);
  _sync(b, a);
}

/// A document holding one paragraph with one text node.
({CollabDoc doc, CollabId paragraph, CollabId text}) _seed(
  int clientId, [
  String initial = '',
]) {
  final doc = CollabDoc(clientId: clientId);
  final paragraph = doc.insertNode(doc.root, 0, 'paragraph');
  final text = doc.insertNode(paragraph, 0, 'text');
  if (initial.isNotEmpty) doc.insertText(text, 0, initial);
  return (doc: doc, paragraph: paragraph, text: text);
}

/// Whether every character of [needle] appears in [haystack], in order.
bool _isSubsequence(String needle, String haystack) {
  var at = 0;
  for (final unit in needle.codeUnits) {
    at = haystack.indexOf(String.fromCharCode(unit), at);
    if (at < 0) return false;
    at++;
  }
  return true;
}

void main() {
  group('text', () {
    test('a single peer reads back what it typed', () {
      final seeded = _seed(1, 'hallo');
      seeded.doc.insertText(seeded.text, 5, ' welt');
      expect(seeded.doc.textOf(seeded.text), 'hallo welt');
    });

    test('inserting in the middle lands in the middle', () {
      final seeded = _seed(1, 'hallo');
      seeded.doc.insertText(seeded.text, 2, 'XY');
      expect(seeded.doc.textOf(seeded.text), 'haXYllo');
    });

    test('deleting removes exactly the range asked for', () {
      final seeded = _seed(1, 'abcdef');
      seeded.doc.deleteRange(seeded.text, 1, 3);
      expect(seeded.doc.textOf(seeded.text), 'aef');
    });

    test('deleting across two runs works', () {
      final seeded = _seed(1, 'abc');
      seeded.doc.insertText(seeded.text, 0, 'XYZ');
      expect(seeded.doc.textOf(seeded.text), 'XYZabc');
      seeded.doc.deleteRange(seeded.text, 2, 2);
      expect(seeded.doc.textOf(seeded.text), 'XYbc');
    });
  });

  group('convergence', () {
    test('two peers typing at the same spot agree on the result', () {
      final a = _seed(1, 'hallo');
      final b = CollabDoc(clientId: 2);
      _sync(a.doc, b);
      expect(b.textOf(a.text), 'hallo');

      a.doc.insertText(a.text, 0, 'A');
      b.insertText(a.text, 0, 'B');
      _syncBoth(a.doc, b);

      // Which of the two goes first is decided by the ids, not by luck — but
      // whichever it is, both peers must say the same thing.
      expect(a.doc.textOf(a.text), b.textOf(a.text));
      expect(a.doc.textOf(a.text), anyOf('ABhallo', 'BAhallo'));
    });

    test('a delete and an insert at the same spot both survive', () {
      final a = _seed(1, 'abcdef');
      final b = CollabDoc(clientId: 2);
      _sync(a.doc, b);

      a.doc.deleteRange(a.text, 1, 2);
      b.insertText(a.text, 2, 'X');
      _syncBoth(a.doc, b);

      expect(a.doc.textOf(a.text), b.textOf(a.text));
      expect(a.doc.textOf(a.text), contains('X'));
      expect(a.doc.textOf(a.text), isNot(contains('b')));
    });

    test('three peers editing at once converge', () {
      final a = _seed(1, 'stamm');
      final b = CollabDoc(clientId: 2);
      final c = CollabDoc(clientId: 3);
      _sync(a.doc, b);
      _sync(a.doc, c);

      a.doc.insertText(a.text, 5, '-A');
      b.insertText(a.text, 0, 'B-');
      c.insertText(a.text, 2, '-C-');

      // Deliberately lopsided: c hears about b only through a.
      _sync(a.doc, b);
      _sync(b, a.doc);
      _sync(a.doc, c);
      _sync(c, a.doc);
      _sync(a.doc, b);

      expect(a.doc.textOf(a.text), b.textOf(a.text));
      expect(b.textOf(a.text), c.textOf(a.text));
      final merged = a.doc.textOf(a.text);
      for (final fragment in ['-A', 'B-', '-C-']) {
        expect(merged, contains(fragment));
      }
      // The original characters are all still there and still in order; one
      // peer typed *into* the middle of the word, which is allowed to break
      // it up but never to lose or reorder it.
      expect(_isSubsequence('stamm', merged), isTrue, reason: merged);
    });

    test('applying the same update twice changes nothing', () {
      final a = _seed(1, 'hallo');
      final b = CollabDoc(clientId: 2);
      final update = a.doc.encodeStateAsUpdate();
      b
        ..applyUpdate(update)
        ..applyUpdate(update);
      expect(b.textOf(a.text), 'hallo');
      expect(b.childrenOf(b.root).length, 1);
    });

    test('an update that arrives before its dependency still lands', () {
      final a = _seed(1, 'eins');
      final first = a.doc.takeUpdate()!;
      a.doc.insertText(a.text, 4, ' zwei');
      final second = a.doc.takeUpdate()!;

      final b = CollabDoc(clientId: 2);
      // The second message overtakes the first, which is what an unordered
      // transport does. It has to be held, not dropped.
      b.applyUpdate(second);
      expect(b.textOf(a.text), '');
      b.applyUpdate(first);
      expect(b.textOf(a.text), 'eins zwei');
    });

    test('a state vector does not claim work that is still waiting', () {
      final a = _seed(1, 'eins');
      final first = a.doc.takeUpdate()!;
      a.doc.insertText(a.text, 4, ' zwei');
      final second = a.doc.takeUpdate()!;

      final b = CollabDoc(clientId: 2)..applyUpdate(second);
      // b has seen the later ids but cannot use them. If its state vector
      // claimed them, nobody would ever send the piece in between.
      final missing = a.doc.encodeStateAsUpdate(b.encodeStateVector());
      b.applyUpdate(missing);
      expect(b.textOf(a.text), 'eins zwei');
      expect(first, isNotNull);
    });
  });

  group('the tree', () {
    test('children keep their order across peers', () {
      final a = CollabDoc(clientId: 1);
      final first = a.insertNode(a.root, 0, 'paragraph');
      final third = a.insertNode(a.root, 1, 'quote');
      final b = CollabDoc(clientId: 2);
      _sync(a, b);

      final second = b.insertNode(b.root, 1, 'heading');
      _syncBoth(a, b);

      expect(a.childrenOf(a.root), [first, second, third]);
      expect(b.childrenOf(b.root), a.childrenOf(a.root));
      expect(a.typeOf(second), 'heading');
    });

    test('a node deleted by one peer is gone for both', () {
      final a = CollabDoc(clientId: 1);
      final paragraph = a.insertNode(a.root, 0, 'paragraph');
      a.insertNode(a.root, 1, 'quote');
      final b = CollabDoc(clientId: 2);
      _sync(a, b);

      a.detachNode(a.root, paragraph);
      _syncBoth(a, b);
      expect(a.childrenOf(a.root).length, 1);
      expect(b.childrenOf(b.root), a.childrenOf(a.root));
    });

    test('a move keeps the subtree, rather than copying it', () {
      final a = CollabDoc(clientId: 1);
      final from = a.insertNode(a.root, 0, 'paragraph');
      final to = a.insertNode(a.root, 1, 'quote');
      final text = a.insertNode(from, 0, 'text');
      a.insertText(text, 0, 'inhalt');

      a
        ..detachNode(from, text)
        ..attachNode(to, 0, text);
      expect(a.childrenOf(from), isEmpty);
      expect(a.childrenOf(to), [text]);
      expect(a.textOf(text), 'inhalt');

      final b = CollabDoc(clientId: 2);
      _sync(a, b);
      expect(b.childrenOf(to), [text]);
      expect(b.textOf(text), 'inhalt');
    });

    test('a node moved by two peers at once ends up in exactly one place', () {
      final a = CollabDoc(clientId: 1);
      final home = a.insertNode(a.root, 0, 'paragraph');
      final left = a.insertNode(a.root, 1, 'quote');
      final right = a.insertNode(a.root, 2, 'quote');
      final child = a.insertNode(home, 0, 'text');
      final b = CollabDoc(clientId: 2);
      _sync(a, b);

      a
        ..detachNode(home, child)
        ..attachNode(left, 0, child);
      b
        ..detachNode(home, child)
        ..attachNode(right, 0, child);
      _syncBoth(a, b);

      final places = [
        for (final parent in [home, left, right])
          if (a.childrenOf(parent).contains(child)) parent,
      ];
      expect(places.length, 1);
      expect(b.childrenOf(places.single), contains(child));
    });
  });

  group('properties', () {
    test('the later write wins', () {
      final a = CollabDoc(clientId: 1);
      final node = a.insertNode(a.root, 0, 'paragraph');
      final b = CollabDoc(clientId: 2);
      _sync(a, b);

      a.setProperty(node, 'format', 'left');
      _syncBoth(a, b);
      b.setProperty(node, 'format', 'center');
      _syncBoth(a, b);

      expect(a.propsOf(node)['format'], 'center');
      expect(b.propsOf(node)['format'], 'center');
    });

    test('concurrent writes resolve the same way on both peers', () {
      final a = CollabDoc(clientId: 1);
      final node = a.insertNode(a.root, 0, 'paragraph');
      final b = CollabDoc(clientId: 2);
      _sync(a, b);

      a.setProperty(node, 'indent', 1);
      b.setProperty(node, 'indent', 2);
      _syncBoth(a, b);

      expect(a.propsOf(node)['indent'], b.propsOf(node)['indent']);
    });

    test('structured values survive the round trip', () {
      final a = CollabDoc(clientId: 1);
      final node = a.insertNode(a.root, 0, 'table');
      a.setProperty(node, 'colWidths', [92, 140]);
      final b = CollabDoc(clientId: 2);
      _sync(a, b);
      expect(b.propsOf(node)['colWidths'], [92, 140]);
    });
  });

  group('the wire', () {
    test('nothing to say produces no message', () {
      final a = _seed(1, 'hallo');
      expect(a.doc.takeUpdate(), isNotNull);
      expect(a.doc.takeUpdate(), isNull);
    });

    test('an incremental update carries only what is new', () {
      final a = _seed(1, 'ein ziemlich langer absatz voller zeichen');
      final full = a.doc.takeUpdate()!;
      a.doc.insertText(a.text, 0, 'x');
      final delta = a.doc.takeUpdate()!;
      // The point of the state vector: a keystroke costs a keystroke.
      expect(delta.length, lessThan(full.length ~/ 2));
    });

    test('typing runs merge instead of costing an item each', () {
      final a = _seed(1);
      for (var i = 0; i < 200; i++) {
        a.doc.insertText(a.text, i, 'x');
      }
      expect(a.doc.textOf(a.text).length, 200);
      // 200 separate items would put 200 headers on the wire.
      expect(a.doc.takeUpdate()!.length, lessThan(400));
    });

    test('a foreign or truncated message is rejected, not guessed at', () {
      final doc = CollabDoc(clientId: 1);
      expect(
        () => doc.applyUpdate(Uint8List.fromList([1, 2, 3, 4, 5])),
        throwsA(isA<CollabDecodeException>()),
      );
      final valid = _seed(2, 'hallo').doc.encodeStateAsUpdate();
      expect(
        () => doc.applyUpdate(valid.sublist(0, valid.length - 3)),
        throwsA(isA<CollabDecodeException>()),
      );
    });

    test('an absurd item count is refused before anything is allocated', () {
      final writer = [0x4c, 0x58, 0x43, 0x31, 0xff, 0xff, 0xff, 0xff, 0x7f];
      expect(
        () => CollabDoc(clientId: 1).applyUpdate(Uint8List.fromList(writer)),
        throwsA(isA<CollabDecodeException>()),
      );
    });
  });

  group('changed nodes', () {
    test('an update reports exactly the nodes it touched', () {
      final a = _seed(1, 'hallo');
      final b = CollabDoc(clientId: 2);
      _sync(a.doc, b);

      a.doc.insertText(a.text, 5, '!');
      final changed = b.applyUpdate(a.doc.takeUpdate()!);
      expect(changed, contains(a.text));
      expect(changed, isNot(contains(b.root)));
    });
  });
}
