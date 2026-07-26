/// The caret-anchored suggestion popover.
library;

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:lexical_core/lexical_core.dart';
import 'package:lexical_flutter/lexical_flutter.dart';
import 'package:lexical_mention/lexical_mention.dart';

import 'mention_context.dart';

/// Builds one row of the suggestion list.
typedef MentionItemBuilder =
    Widget Function(
      BuildContext context,
      MentionSuggestion suggestion,
      bool highlighted,
    );

/// Builds the editable the popover is anchored to.
///
/// The key must be passed to a [LexicalEditable]: it is how the popover
/// reaches the caret's geometry. Handing it to the builder rather than asking
/// for one removes the failure mode where it is simply forgotten.
typedef MentionEditableBuilder =
    Widget Function(BuildContext context, GlobalKey<LexicalEditableState> key);

/// Wires mention typeahead onto a [LexicalEditable].
///
/// ```dart
/// MentionScope(
///   editor: editor,
///   triggers: const [MentionTrigger(character: '@', mentionType: 'user')],
///   source: CallbackMentionSource(search),
///   itemBuilder: (context, suggestion, highlighted) => …,
///   builder: (context, key) => LexicalEditable(key: key, …),
/// )
/// ```
///
/// The popover lives in an [Overlay], so it is never clipped by the editor's
/// scroll view, and it takes no focus, so the caret keeps blinking and the
/// software keyboard stays up while the user picks.
class MentionScope extends StatefulWidget {
  /// Creates a typeahead over [editor].
  const MentionScope({
    required this.editor,
    required this.triggers,
    required this.source,
    required this.itemBuilder,
    required this.builder,
    super.key,
    this.debounce = const Duration(milliseconds: 150),
    this.limit = 8,
    this.width = 280,
    this.maxHeight = 240,
    this.gap = 4,
    this.decoration,
    this.emptyBuilder,
    this.loadingBuilder,
    this.label = defaultMentionLabel,
    this.trailingSpace = true,
    this.onInserted,
  });

  /// The editor mentions are inserted into.
  final LexicalEditor editor;

  /// What opens a picker, and which kind of entity each one names.
  final List<MentionTrigger> triggers;

  /// Where suggestions come from.
  final MentionSource source;

  /// Builds one suggestion row.
  final MentionItemBuilder itemBuilder;

  /// Builds the editable, which must carry the supplied key.
  final MentionEditableBuilder builder;

  /// How long to wait after the last keystroke before searching.
  final Duration debounce;

  /// How many suggestions to request.
  final int limit;

  /// Popover width in logical pixels.
  final double width;

  /// Greatest popover height before the list scrolls.
  final double maxHeight;

  /// Space between the caret and the popover.
  final double gap;

  /// Popover chrome. A plain box when omitted.
  final Decoration? decoration;

  /// Shown when a search returned nothing. Hidden when omitted.
  final WidgetBuilder? emptyBuilder;

  /// Shown while a search is in flight and nothing is on screen yet.
  final WidgetBuilder? loadingBuilder;

  /// Builds the text an inserted mention carries.
  final MentionLabelBuilder label;

  /// Whether to insert a space after the mention.
  final bool trailingSpace;

  /// Called after a suggestion was inserted.
  final void Function(MentionSuggestion suggestion)? onInserted;

  @override
  State<MentionScope> createState() => MentionScopeState();
}

/// State of a [MentionScope]; exposed so a host can drive it programmatically.
class MentionScopeState extends State<MentionScope> {
  final GlobalKey<LexicalEditableState> _editableKey =
      GlobalKey<LexicalEditableState>();
  late MentionSearchController _controller;
  late int _lookback;
  StreamSubscription<MentionSearchState>? _subscription;
  Unsubscribe? _unsubscribeEditor;
  Unsubscribe? _unsubscribeKeys;
  OverlayEntry? _entry;
  MentionSearchState _state = const MentionSearchState();

  /// The current picker state.
  MentionSearchState get state => _state;

  /// Whether the picker is on screen.
  bool get isOpen => _entry != null;

  @override
  void initState() {
    super.initState();
    _controller = _createController();
    _subscription = _controller.states.listen(_onSearchState);
    _unsubscribeEditor = widget.editor.registerUpdateListener(_onCommit);
    // Critical priority: the arrow keys have to reach the list before the
    // editor moves the caret with them, or the picker can never be navigated.
    _unsubscribeKeys = widget.editor.registerCommand<KeyEvent>(
      keyDownCommand,
      _onKey,
      CommandPriority.critical,
    );
  }

  @override
  void didUpdateWidget(MentionScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.triggers != widget.triggers ||
        oldWidget.source != widget.source ||
        oldWidget.debounce != widget.debounce ||
        oldWidget.limit != widget.limit) {
      _subscription?.cancel();
      _controller.dispose();
      _controller = _createController();
      _subscription = _controller.states.listen(_onSearchState);
    }
  }

  @override
  void dispose() {
    _unsubscribeKeys?.call();
    _unsubscribeEditor?.call();
    _subscription?.cancel();
    _controller.dispose();
    _removeOverlay();
    super.dispose();
  }

  MentionSearchController _createController() {
    var longest = 0;
    for (final trigger in widget.triggers) {
      if (trigger.maxQueryLength > longest) longest = trigger.maxQueryLength;
    }
    // Two characters of slack past the longest query, so the character before
    // a trigger is always available for the word-boundary test.
    _lookback = longest + 2;
    return MentionSearchController(
      triggers: widget.triggers,
      source: widget.source,
      debounce: widget.debounce,
      limit: widget.limit,
    );
  }

  // -------------------------------------------------------------------
  // Model to picker
  // -------------------------------------------------------------------

  void _onCommit(EditorUpdate update) {
    final context = widget.editor.read(
      () => $textBeforeCaret(limit: _lookback),
    );
    if (context == null) {
      _controller.close();
      return;
    }
    _controller.onTextChanged(context.text, context.caretOffset);
  }

  void _onSearchState(MentionSearchState state) {
    _state = state;
    if (!mounted) return;
    // Inserting an overlay entry marks the Overlay dirty, so this cannot run
    // during a build — and it can be reached from one: a commit landing
    // mid-build reaches the controller, and a cached answer is emitted
    // synchronously.
    whenBuildIsDone(() {
      if (!mounted) return;
      if (_state.isOpen) {
        _showOverlay();
      } else {
        _removeOverlay();
      }
    });
  }

  // -------------------------------------------------------------------
  // Keyboard
  // -------------------------------------------------------------------

  bool _onKey(KeyEvent event) {
    if (!isOpen) return false;
    if (event is KeyUpEvent) return false;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowDown:
        _controller.moveHighlight(1);
        return true;
      case LogicalKeyboardKey.arrowUp:
        _controller.moveHighlight(-1);
        return true;
      case LogicalKeyboardKey.enter:
      case LogicalKeyboardKey.numpadEnter:
      case LogicalKeyboardKey.tab:
        final highlighted = _state.highlighted;
        if (highlighted == null) return false;
        accept(highlighted);
        return true;
      case LogicalKeyboardKey.escape:
        _controller.close();
        return true;
    }
    return false;
  }

  // -------------------------------------------------------------------
  // Insertion
  // -------------------------------------------------------------------

  /// Inserts [suggestion] in place of the trigger that opened the picker.
  void accept(MentionSuggestion suggestion) {
    final match = _state.match;
    if (match == null) return;
    // runUpdate, not update: this is reachable from a command handler, which
    // is already inside one.
    widget.editor.runUpdate(() {
      $insertMention(
        match: match,
        suggestion: suggestion,
        label: widget.label,
        trailingSpace: widget.trailingSpace,
      );
    });
    _controller.close();
    widget.onInserted?.call(suggestion);
  }

  /// Closes the picker without inserting anything.
  void cancel() => _controller.close();

  // -------------------------------------------------------------------
  // Overlay
  // -------------------------------------------------------------------

  void _showOverlay() {
    final entry = _entry;
    if (entry != null) {
      entry.markNeedsBuild();
      return;
    }
    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return;
    _entry = OverlayEntry(builder: _buildOverlay);
    overlay.insert(_entry!);
  }

  void _removeOverlay() {
    _entry?.remove();
    _entry = null;
  }

  Widget _buildOverlay(BuildContext overlayContext) {
    final caret = _editableKey.currentState?.caretRect;
    final overlayBox = Overlay.of(context).context.findRenderObject();
    if (caret == null || overlayBox is! RenderBox) {
      return const SizedBox.shrink();
    }
    final topLeft = overlayBox.globalToLocal(caret.bottomLeft);
    final size = overlayBox.size;

    final below = size.height - topLeft.dy - widget.gap;
    final above = topLeft.dy - caret.height - widget.gap;
    // Flip above the caret when there is not enough room below it, which on a
    // phone with the keyboard up is most of the time.
    final flip = below < widget.maxHeight && above > below;
    final height = (flip ? above : below).clamp(0.0, widget.maxHeight);
    if (height <= 0) return const SizedBox.shrink();

    final maxLeft = (size.width - widget.width).clamp(0.0, size.width);
    final left = topLeft.dx.clamp(0.0, maxLeft);

    return Positioned(
      left: left,
      top: flip ? null : topLeft.dy + widget.gap,
      bottom: flip
          ? size.height - topLeft.dy + caret.height + widget.gap
          : null,
      width: widget.width,
      // An overlay entry is a sibling of the whole app, not a descendant of
      // this widget, so nothing it inherits comes for free — including the
      // text style. Without this, rows render in Flutter's red 48-point
      // "you forgot a Material" fallback, which looks like a bug in the item
      // builder and is not.
      child: _inherit(
        _MentionList(
          state: _state,
          itemBuilder: widget.itemBuilder,
          emptyBuilder: widget.emptyBuilder,
          loadingBuilder: widget.loadingBuilder,
          decoration: widget.decoration,
          maxHeight: height,
          onSelected: accept,
        ),
      ),
    );
  }

  Widget _inherit(Widget child) => InheritedTheme.captureAll(
    context,
    Directionality(
      textDirection: Directionality.maybeOf(context) ?? TextDirection.ltr,
      child: DefaultTextStyle(
        style: DefaultTextStyle.of(context).style,
        child: MediaQuery(data: MediaQuery.of(context), child: child),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    // The overlay is rebuilt after the frame so it sees the caret's new
    // geometry rather than the one from before this build.
    if (_entry != null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _entry?.markNeedsBuild(),
      );
    }
    return widget.builder(context, _editableKey);
  }
}

class _MentionList extends StatelessWidget {
  const _MentionList({
    required this.state,
    required this.itemBuilder,
    required this.maxHeight,
    required this.onSelected,
    this.emptyBuilder,
    this.loadingBuilder,
    this.decoration,
  });

  final MentionSearchState state;
  final MentionItemBuilder itemBuilder;
  final WidgetBuilder? emptyBuilder;
  final WidgetBuilder? loadingBuilder;
  final Decoration? decoration;
  final double maxHeight;
  final void Function(MentionSuggestion suggestion) onSelected;

  @override
  Widget build(BuildContext context) {
    final Widget body;
    if (state.suggestions.isEmpty) {
      final builder = state.isLoading ? loadingBuilder : emptyBuilder;
      if (builder == null) return const SizedBox.shrink();
      body = builder(context);
    } else {
      body = ListView.builder(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        itemCount: state.suggestions.length,
        itemBuilder: (context, index) {
          final suggestion = state.suggestions[index];
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onSelected(suggestion),
            child: itemBuilder(
              context,
              suggestion,
              index == state.highlightedIndex,
            ),
          );
        },
      );
    }

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: DecoratedBox(
        decoration: decoration ?? const BoxDecoration(),
        child: body,
      ),
    );
  }
}
