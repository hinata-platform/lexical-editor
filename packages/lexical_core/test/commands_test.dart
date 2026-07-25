import 'package:lexical_core/lexical_core.dart';
import 'package:test/test.dart';

const testCommand = LexicalCommand<String>('TEST');
const voidCommand = LexicalCommand<void>('VOID');

void main() {
  group('dispatch order', () {
    test('walks from critical down to editor', () {
      final editor = LexicalEditor();
      final order = <String>[];
      final subscriptions = <Unsubscribe>[
        editor.registerCommand(testCommand, (_) {
          order.add('editor');
          return false;
        }, CommandPriority.editor),
        editor.registerCommand(testCommand, (_) {
          order.add('critical');
          return false;
        }, CommandPriority.critical),
        editor.registerCommand(testCommand, (_) {
          order.add('normal');
          return false;
        }, CommandPriority.normal),
        editor.registerCommand(testCommand, (_) {
          order.add('high');
          return false;
        }, CommandPriority.high),
        editor.registerCommand(testCommand, (_) {
          order.add('low');
          return false;
        }, CommandPriority.low),
      ];

      expect(editor.dispatchCommand(testCommand, 'x'), isFalse);
      expect(order, ['critical', 'high', 'normal', 'low', 'editor']);
      for (final unsubscribe in subscriptions) {
        unsubscribe();
      }
    });

    test('stops at the first handler that returns true', () {
      final editor = LexicalEditor();
      final order = <String>[];
      editor
        ..registerCommand(testCommand, (_) {
          order.add('editor');
          return false;
        }, CommandPriority.editor)
        ..registerCommand(testCommand, (_) {
          order.add('normal');
          return true;
        }, CommandPriority.normal)
        ..registerCommand(testCommand, (_) {
          order.add('critical');
          return false;
        }, CommandPriority.critical);

      expect(editor.dispatchCommand(testCommand, 'x'), isTrue);
      expect(order, ['critical', 'normal']);
    });

    test('plain handlers at one level run in registration order', () {
      final editor = LexicalEditor();
      final order = <String>[];
      for (final name in ['first', 'second', 'third']) {
        editor.registerCommand(testCommand, (_) {
          order.add(name);
          return false;
        }, CommandPriority.normal);
      }
      editor.dispatchCommand(testCommand, 'x');
      expect(order, ['first', 'second', 'third']);
    });

    test('before handlers run most-recently-registered first', () {
      final editor = LexicalEditor();
      final order = <String>[];
      for (final name in ['first', 'second', 'third']) {
        editor.registerCommand(testCommand, (_) {
          order.add(name);
          return false;
        }, CommandPriority.beforeNormal);
      }
      editor.dispatchCommand(testCommand, 'x');
      expect(order, [
        'third',
        'second',
        'first',
      ], reason: 'before* registrations prepend within their level');
    });

    test('before handlers precede plain handlers at the same level', () {
      final editor = LexicalEditor();
      final order = <String>[];
      editor
        ..registerCommand(testCommand, (_) {
          order.add('plain');
          return false;
        }, CommandPriority.normal)
        ..registerCommand(testCommand, (_) {
          order.add('before');
          return false;
        }, CommandPriority.beforeNormal);
      editor.dispatchCommand(testCommand, 'x');
      expect(order, ['before', 'plain']);
    });

    test('beforeEditor lets a consumer override a package default', () {
      final editor = LexicalEditor();
      final order = <String>[];
      editor
        ..registerCommand(testCommand, (_) {
          order.add('package default');
          return true;
        }, CommandPriority.editor)
        ..registerCommand(testCommand, (_) {
          order.add('app override');
          return true;
        }, CommandPriority.beforeEditor);
      editor.dispatchCommand(testCommand, 'x');
      expect(order, ['app override']);
    });
  });

  group('payloads', () {
    test('are delivered with their declared type', () {
      final editor = LexicalEditor();
      String? received;
      editor.registerCommand(testCommand, (payload) {
        received = payload;
        return true;
      }, CommandPriority.editor);
      editor.dispatchCommand(testCommand, 'hallo');
      expect(received, 'hallo');
    });

    test('void commands dispatch with null', () {
      final editor = LexicalEditor();
      var called = false;
      editor.registerCommand(voidCommand, (_) {
        called = true;
        return true;
      }, CommandPriority.editor);
      expect(editor.dispatchCommand(voidCommand, null), isTrue);
      expect(called, isTrue);
    });
  });

  group('lifecycle', () {
    test('unsubscribing stops delivery', () {
      final editor = LexicalEditor();
      var calls = 0;
      final unsubscribe = editor.registerCommand(testCommand, (_) {
        calls++;
        return true;
      }, CommandPriority.editor);

      editor.dispatchCommand(testCommand, 'x');
      unsubscribe();
      editor.dispatchCommand(testCommand, 'x');
      expect(calls, 1);
    });

    test('a handler may unregister itself during dispatch', () {
      final editor = LexicalEditor();
      var calls = 0;
      late Unsubscribe unsubscribe;
      unsubscribe = editor.registerCommand(testCommand, (_) {
        calls++;
        unsubscribe();
        return false;
      }, CommandPriority.editor);

      editor
        ..dispatchCommand(testCommand, 'x')
        ..dispatchCommand(testCommand, 'x');
      expect(calls, 1);
    });

    test('dispatching an unhandled command is not an error', () {
      final editor = LexicalEditor();
      expect(editor.dispatchCommand(testCommand, 'x'), isFalse);
    });
  });

  group('dispatch opens an update', () {
    test('a handler may mutate without opening one itself', () {
      final editor = LexicalEditor();
      editor.registerCommand(testCommand, (payload) {
        $getRoot().append(
          $createParagraphNode()..append($createTextNode(payload)),
        );
        return true;
      }, CommandPriority.editor);

      editor.dispatchCommand(testCommand, 'aus einem Handler');
      expect(
        editor.read(() => $getRoot().getTextContent()),
        'aus einem Handler',
      );
    });

    test('a dispatch from inside an update joins it', () {
      final editor = LexicalEditor();
      editor.registerCommand(testCommand, (_) {
        $getRoot().append($createParagraphNode());
        return true;
      }, CommandPriority.editor);

      editor.update(() {
        $getRoot().append($createParagraphNode());
        editor.dispatchCommand(testCommand, 'x');
      }, discrete: true);

      expect(editor.read(() => $getRoot().childrenSize), 2);
    });

    test('runaway recursion is caught rather than hanging', () {
      final editor = LexicalEditor();
      editor.registerCommand(testCommand, (payload) {
        editor.dispatchCommand(testCommand, payload);
        return true;
      }, CommandPriority.editor);

      expect(
        () => editor.dispatchCommand(testCommand, 'x'),
        throwsA(isA<LexicalStateError>()),
      );
    });
  });
}
