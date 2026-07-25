/// Searching for mention suggestions: debounce, cancellation and caching.
///
/// All of it is pure Dart on purpose. Debouncing, dropping stale responses
/// and caching are precisely the parts that are hard to get right and hard to
/// test through a widget, so they live where a plain `dart test` can drive
/// them with a fake clock and a fake source.
library;

import 'dart:async';
import 'dart:collection';

import 'package:meta/meta.dart';

import 'mention_trigger.dart';

/// One entity offered to the user.
@immutable
class MentionSuggestion {
  /// Describes a selectable suggestion.
  const MentionSuggestion({
    required this.id,
    required this.label,
    required this.mentionType,
    this.subtitle,
    this.imageUrl,
    this.data = const {},
  });

  /// Stable identifier of the referenced entity.
  final String id;

  /// The text shown in the list, and the mention's label once inserted.
  ///
  /// **Without the trigger character.** The label builder prepends it, so a
  /// label of `#108` for a `#` trigger inserts `##108` — a mistake that looks
  /// like a rendering bug and is really in the search result.
  final String label;

  /// The kind of thing this is.
  final String mentionType;

  /// Secondary line, such as an email address or an issue title.
  final String? subtitle;

  /// Avatar or icon URL.
  final String? imageUrl;

  /// Extra data carried onto the inserted node's state.
  final Map<String, Object?> data;

  @override
  bool operator ==(Object other) =>
      other is MentionSuggestion &&
      other.id == id &&
      other.mentionType == mentionType &&
      other.label == label;

  @override
  int get hashCode => Object.hash(id, mentionType, label);

  @override
  String toString() => 'MentionSuggestion($mentionType:$id, $label)';
}

/// What the controller asks a source for.
@immutable
class MentionQuery {
  /// Asks for suggestions of [mentionType] matching [text].
  const MentionQuery({
    required this.text,
    required this.mentionType,
    this.limit = 8,
  });

  /// The typed query, without the trigger character.
  final String text;

  /// Which kind of entity to search.
  final String mentionType;

  /// How many suggestions to return at most.
  final int limit;

  @override
  bool operator ==(Object other) =>
      other is MentionQuery &&
      other.text == text &&
      other.mentionType == mentionType &&
      other.limit == limit;

  @override
  int get hashCode => Object.hash(text, mentionType, limit);

  @override
  String toString() => 'MentionQuery($mentionType, "$text")';
}

/// Supplies suggestions for a query.
///
/// Implementations should be cancellation-tolerant: the controller drops
/// results that arrive after a newer query started, but it cannot stop work
/// already in flight.
abstract interface class MentionSource {
  /// Returns suggestions for [query].
  Future<List<MentionSuggestion>> search(MentionQuery query);
}

/// A source backed by a plain function.
class CallbackMentionSource implements MentionSource {
  /// Wraps [onSearch] as a source.
  const CallbackMentionSource(this.onSearch);

  /// The function performing the search.
  final Future<List<MentionSuggestion>> Function(MentionQuery query) onSearch;

  @override
  Future<List<MentionSuggestion>> search(MentionQuery query) => onSearch(query);
}

/// What the picker should currently show.
@immutable
class MentionSearchState {
  /// Describes the picker's state.
  const MentionSearchState({
    this.match,
    this.suggestions = const [],
    this.isLoading = false,
    this.highlightedIndex = 0,
    this.error,
  });

  /// The trigger match driving the search, or `null` when closed.
  final MentionMatch? match;

  /// The suggestions to show.
  final List<MentionSuggestion> suggestions;

  /// Whether a request is in flight.
  final bool isLoading;

  /// Which suggestion the keyboard is on.
  final int highlightedIndex;

  /// The last error, if the source failed.
  final Object? error;

  /// Whether the picker should be visible.
  ///
  /// Stays open while loading so it does not flicker between keystrokes.
  bool get isOpen => match != null && (isLoading || suggestions.isNotEmpty);

  /// The suggestion the keyboard is on, or `null`.
  MentionSuggestion? get highlighted =>
      highlightedIndex >= 0 && highlightedIndex < suggestions.length
      ? suggestions[highlightedIndex]
      : null;

  /// Returns a copy with the given fields replaced.
  MentionSearchState copyWith({
    MentionMatch? match,
    List<MentionSuggestion>? suggestions,
    bool? isLoading,
    int? highlightedIndex,
    Object? error,
    bool clearMatch = false,
    bool clearError = false,
  }) => MentionSearchState(
    match: clearMatch ? null : (match ?? this.match),
    suggestions: suggestions ?? this.suggestions,
    isLoading: isLoading ?? this.isLoading,
    highlightedIndex: highlightedIndex ?? this.highlightedIndex,
    error: clearError ? null : (error ?? this.error),
  );

  @override
  String toString() =>
      'MentionSearchState(match: $match, ${suggestions.length} suggestions, '
      'loading: $isLoading)';
}

/// Drives mention search: debounce, stale-response rejection and caching.
///
/// Feed it the text before the caret on every change; it decides whether a
/// trigger is active, when to search, and what the picker should show.
class MentionSearchController {
  /// Creates a controller over [triggers] backed by [source].
  MentionSearchController({
    required this.triggers,
    required this.source,
    this.debounce = const Duration(milliseconds: 150),
    this.limit = 8,
    this.cacheSize = 32,
  });

  /// The triggers that open a picker.
  final List<MentionTrigger> triggers;

  /// Where suggestions come from.
  final MentionSource source;

  /// How long to wait after the last keystroke before searching.
  ///
  /// Without it, typing an eight-character name fires eight requests and the
  /// list flickers through seven answers nobody wanted.
  final Duration debounce;

  /// How many suggestions to request.
  final int limit;

  /// How many recent queries to remember.
  ///
  /// Backspacing through a query re-asks for answers already seen, so a small
  /// cache turns the most common interaction into zero requests.
  final int cacheSize;

  final _controller = StreamController<MentionSearchState>.broadcast();
  final LinkedHashMap<MentionQuery, List<MentionSuggestion>> _cache =
      LinkedHashMap<MentionQuery, List<MentionSuggestion>>();

  MentionSearchState _state = const MentionSearchState();
  Timer? _debounceTimer;
  int _requestGeneration = 0;
  bool _disposed = false;

  /// The current state.
  MentionSearchState get state => _state;

  /// Emits whenever [state] changes.
  Stream<MentionSearchState> get states => _controller.stream;

  /// Re-evaluates the trigger for [text] with the caret at [caretOffset].
  ///
  /// Cheap enough to call on every keystroke: matching looks back a bounded
  /// number of characters, and an unchanged query does not restart the search.
  void onTextChanged(String text, int caretOffset) {
    if (_disposed) return;
    final match = matchMentionTrigger(text, caretOffset, triggers);
    if (match == null) {
      close();
      return;
    }
    final previous = _state.match;
    if (previous != null &&
        previous.trigger == match.trigger &&
        previous.query == match.query) {
      // Same query, moved caret or unrelated edit: keep what is on screen.
      _emit(_state.copyWith(match: match));
      return;
    }

    final query = MentionQuery(
      text: match.query,
      mentionType: match.trigger.mentionType,
      limit: limit,
    );

    final cached = _cache[query];
    if (cached != null) {
      _debounceTimer?.cancel();
      // Bump the generation so a slower in-flight request cannot overwrite
      // the cached answer we are about to show.
      _requestGeneration++;
      _emit(
        MentionSearchState(
          match: match,
          suggestions: cached,
          highlightedIndex: 0,
        ),
      );
      return;
    }

    _emit(
      _state.copyWith(
        match: match,
        isLoading: true,
        highlightedIndex: 0,
        clearError: true,
      ),
    );

    _debounceTimer?.cancel();
    if (debounce == Duration.zero) {
      _search(query);
    } else {
      _debounceTimer = Timer(debounce, () => _search(query));
    }
  }

  Future<void> _search(MentionQuery query) async {
    final generation = ++_requestGeneration;
    try {
      final results = await source.search(query);
      // A response from a query the user has already typed past must never
      // replace what is on screen — that is the flicker everyone recognises
      // and nobody can reproduce on demand.
      if (_disposed || generation != _requestGeneration) return;
      _remember(query, results);
      _emit(
        _state.copyWith(
          suggestions: results,
          isLoading: false,
          highlightedIndex: 0,
          clearError: true,
        ),
      );
    } on Object catch (error) {
      if (_disposed || generation != _requestGeneration) return;
      _emit(
        _state.copyWith(suggestions: const [], isLoading: false, error: error),
      );
    }
  }

  void _remember(MentionQuery query, List<MentionSuggestion> results) {
    if (cacheSize <= 0) return;
    _cache
      ..remove(query)
      ..[query] = List.unmodifiable(results);
    while (_cache.length > cacheSize) {
      _cache.remove(_cache.keys.first);
    }
  }

  /// Moves the keyboard highlight by [delta], wrapping around.
  void moveHighlight(int delta) {
    final count = _state.suggestions.length;
    if (count == 0) return;
    final next = (_state.highlightedIndex + delta) % count;
    _emit(_state.copyWith(highlightedIndex: next < 0 ? next + count : next));
  }

  /// Closes the picker and cancels anything in flight.
  void close() {
    _debounceTimer?.cancel();
    _debounceTimer = null;
    // Invalidate in-flight requests so a late answer cannot reopen the picker.
    _requestGeneration++;
    if (_state.match == null &&
        _state.suggestions.isEmpty &&
        !_state.isLoading) {
      return;
    }
    _emit(const MentionSearchState());
  }

  /// Empties the query cache.
  void clearCache() => _cache.clear();

  void _emit(MentionSearchState next) {
    _state = next;
    if (!_controller.isClosed) _controller.add(next);
  }

  /// Releases the timer and the stream.
  void dispose() {
    _disposed = true;
    _debounceTimer?.cancel();
    _controller.close();
  }
}
