import 'dart:async';

import 'package:lexical_mention/lexical_mention.dart';
import 'package:test/test.dart';

const user = MentionTrigger(character: '@', mentionType: 'user');

/// A source that records every query and can be made to answer slowly.
class RecordingSource implements MentionSource {
  RecordingSource({this.delay = Duration.zero, this.failWith});

  final Duration delay;
  final Object? failWith;
  final List<MentionQuery> queries = [];
  final Map<String, Duration> perQueryDelay = {};

  @override
  Future<List<MentionSuggestion>> search(MentionQuery query) async {
    queries.add(query);
    final wait = perQueryDelay[query.text] ?? delay;
    if (wait > Duration.zero) await Future<void>.delayed(wait);
    if (failWith != null) throw failWith!;
    return [
      MentionSuggestion(
        id: '${query.text}-1',
        label: '${query.text} eins',
        mentionType: query.mentionType,
      ),
      MentionSuggestion(
        id: '${query.text}-2',
        label: '${query.text} zwei',
        mentionType: query.mentionType,
      ),
    ];
  }
}

void main() {
  group('debounce', () {
    test('a burst of keystrokes produces one request', () async {
      final source = RecordingSource();
      final controller = MentionSearchController(
        triggers: const [user],
        source: source,
        debounce: const Duration(milliseconds: 20),
      );
      addTearDown(controller.dispose);

      for (final text in ['@r', '@re', '@reb', '@reba']) {
        controller.onTextChanged(text, text.length);
      }
      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(source.queries, hasLength(1));
      expect(source.queries.single.text, 'reba');
      expect(controller.state.suggestions, hasLength(2));
    });

    test('the picker stays open while loading, so it does not flicker', () {
      final source = RecordingSource(delay: const Duration(milliseconds: 50));
      final controller = MentionSearchController(
        triggers: const [user],
        source: source,
        debounce: Duration.zero,
      );
      addTearDown(controller.dispose);

      controller.onTextChanged('@reb', 4);
      expect(controller.state.isLoading, isTrue);
      expect(controller.state.isOpen, isTrue);
    });
  });

  group('stale responses', () {
    test('a slow answer never replaces a newer one', () async {
      final source = RecordingSource()
        ..perQueryDelay['a'] = const Duration(milliseconds: 80)
        ..perQueryDelay['ab'] = const Duration(milliseconds: 5);
      final controller = MentionSearchController(
        triggers: const [user],
        source: source,
        debounce: Duration.zero,
      );
      addTearDown(controller.dispose);

      controller.onTextChanged('@a', 2);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      controller.onTextChanged('@ab', 3);
      await Future<void>.delayed(const Duration(milliseconds: 150));

      expect(
        controller.state.suggestions.first.id,
        'ab-1',
        reason: 'the answer to a query the user typed past must be dropped',
      );
    });

    test('closing invalidates a request in flight', () async {
      final source = RecordingSource(delay: const Duration(milliseconds: 40));
      final controller = MentionSearchController(
        triggers: const [user],
        source: source,
        debounce: Duration.zero,
      );
      addTearDown(controller.dispose);

      controller.onTextChanged('@reb', 4);
      controller.close();
      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(controller.state.isOpen, isFalse);
      expect(controller.state.suggestions, isEmpty);
    });
  });

  group('cache', () {
    test('backspacing into a seen query costs no request', () async {
      final source = RecordingSource();
      final controller = MentionSearchController(
        triggers: const [user],
        source: source,
        debounce: Duration.zero,
      );
      addTearDown(controller.dispose);

      controller.onTextChanged('@re', 3);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      controller.onTextChanged('@reb', 4);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(source.queries, hasLength(2));

      controller.onTextChanged('@re', 3);
      expect(source.queries, hasLength(2), reason: 'served from cache');
      expect(controller.state.isLoading, isFalse);
      expect(controller.state.suggestions.first.id, 're-1');
    });

    test('the cache is bounded', () async {
      final source = RecordingSource();
      final controller = MentionSearchController(
        triggers: const [user],
        source: source,
        debounce: Duration.zero,
        cacheSize: 2,
      );
      addTearDown(controller.dispose);

      for (final query in ['a', 'b', 'c']) {
        controller.onTextChanged('@$query', query.length + 1);
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      // 'a' was evicted, so asking again really asks.
      controller.onTextChanged('@a', 2);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(source.queries, hasLength(4));
    });
  });

  group('lifecycle', () {
    test('losing the trigger closes the picker', () async {
      final source = RecordingSource();
      final controller = MentionSearchController(
        triggers: const [user],
        source: source,
        debounce: Duration.zero,
      );
      addTearDown(controller.dispose);

      controller.onTextChanged('@reb', 4);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(controller.state.isOpen, isTrue);

      controller.onTextChanged('@reb fertig', 11);
      expect(controller.state.isOpen, isFalse);
      expect(controller.state.match, isNull);
    });

    test('an unchanged query does not restart the search', () async {
      final source = RecordingSource();
      final controller = MentionSearchController(
        triggers: const [user],
        source: source,
        debounce: Duration.zero,
      );
      addTearDown(controller.dispose);

      controller.onTextChanged('@reb', 4);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      controller.onTextChanged('@reb', 4);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(source.queries, hasLength(1));
    });

    test('the highlight wraps in both directions', () async {
      final source = RecordingSource();
      final controller = MentionSearchController(
        triggers: const [user],
        source: source,
        debounce: Duration.zero,
      );
      addTearDown(controller.dispose);

      controller.onTextChanged('@reb', 4);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(controller.state.highlightedIndex, 0);
      controller.moveHighlight(1);
      expect(controller.state.highlightedIndex, 1);
      controller.moveHighlight(1);
      expect(controller.state.highlightedIndex, 0, reason: 'wraps forward');
      controller.moveHighlight(-1);
      expect(controller.state.highlightedIndex, 1, reason: 'wraps backward');
      expect(controller.state.highlighted!.id, 'reb-2');
    });

    test('a failing source surfaces the error and closes the list', () async {
      final source = RecordingSource(failWith: StateError('offline'));
      final controller = MentionSearchController(
        triggers: const [user],
        source: source,
        debounce: Duration.zero,
      );
      addTearDown(controller.dispose);

      controller.onTextChanged('@reb', 4);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(controller.state.error, isA<StateError>());
      expect(controller.state.isLoading, isFalse);
      expect(controller.state.isOpen, isFalse);
    });

    test('state changes are observable as a stream', () async {
      final source = RecordingSource();
      final controller = MentionSearchController(
        triggers: const [user],
        source: source,
        debounce: Duration.zero,
      );
      addTearDown(controller.dispose);

      final seen = <MentionSearchState>[];
      final subscription = controller.states.listen(seen.add);
      addTearDown(subscription.cancel);

      controller.onTextChanged('@reb', 4);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(seen, isNotEmpty);
      expect(seen.last.suggestions, hasLength(2));
    });
  });
}
