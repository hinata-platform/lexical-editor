/// The document widget and its dirty-set reconciler.
library;

import 'package:flutter/widgets.dart';
import 'package:lexical_core/lexical_core.dart';

import '../render/block_offset_map.dart';
import '../render/span_builder.dart';
import '../theme/lexical_theme.dart';
import 'block_registry.dart';
import 'build_phase.dart';
import 'lexical_inline_block.dart';
import 'lexical_interaction.dart';

/// A block's built presentation, cached between commits.
@immutable
class _CachedBlock {
  const _CachedBlock(this.node, this.widget, this.offsets);

  /// The exact node version this was built from.
  final LexicalNode node;

  /// The built widget subtree.
  final Widget widget;

  /// The offset map for the block's own inline run, if it has one.
  final BlockOffsetMap? offsets;
}

/// Counts how much work a commit caused. Test-only.
@visibleForTesting
class LexicalRenderStats {
  /// Number of top-level blocks rebuilt since the last reset.
  int blocksBuilt = 0;

  /// Number of top-level blocks served from the cache.
  int blocksReused = 0;

  /// Clears the counters.
  void reset() {
    blocksBuilt = 0;
    blocksReused = 0;
  }

  @override
  String toString() =>
      'LexicalRenderStats(built: $blocksBuilt, reused: $blocksReused)';
}

/// Renders the document held by a [LexicalEditor].
///
/// This is the read-only view. It is useful on its own — a viewer for
/// documents authored on Lexical web — and it is the substrate the editable
/// widget builds on.
///
/// Rebuilds are driven by the **dirty set** of each commit, not by rebuilding
/// the tree from the state. Lexical already knows which nodes changed; that
/// information is exactly what Flutter needs in order not to rebuild
/// everything, and throwing it away produces a demo that is fast enough until
/// the first real document.
class LexicalDocument extends StatefulWidget {
  /// Renders [editor]'s document with [theme].
  const LexicalDocument({
    required this.editor,
    required this.theme,
    super.key,
    this.decoratorBuilders = const {},
    this.padding = EdgeInsets.zero,
    this.scrollable = true,
    this.scrollController,
    this.textDirection,
    this.textScaler,
    this.interaction,
    this.registry,
    this.stats,
  });

  /// The editor whose document is rendered.
  final LexicalEditor editor;

  /// Styling for text, blocks and markers.
  final LexicalTheme theme;

  /// Widget builders for decorator node types.
  final Map<String, DecoratorBuilder> decoratorBuilders;

  /// Padding around the document.
  final EdgeInsetsGeometry padding;

  /// Whether to scroll, using a lazily built list that culls off-screen
  /// blocks.
  ///
  /// Turn it off when embedding the document inside another scrollable.
  final bool scrollable;

  /// Controller for the internal scroll view.
  final ScrollController? scrollController;

  /// Overrides the ambient text direction.
  final TextDirection? textDirection;

  /// Overrides the ambient text scaler.
  final TextScaler? textScaler;

  /// Which node types respond to hover and tap, and how.
  ///
  /// Left null the document is inert: no mouse tracking, no gesture
  /// recognizer, nothing hit-tested.
  final LexicalInteraction? interaction;

  /// A registry to publish mounted blocks into.
  ///
  /// Supplied by the editable layer, which needs to reach render objects to
  /// paint carets and selections without rebuilding widgets. A read-only
  /// document creates its own.
  final BlockRegistry? registry;

  /// Test-only rebuild counters.
  @visibleForTesting
  final LexicalRenderStats? stats;

  @override
  State<LexicalDocument> createState() => LexicalDocumentState();
}

/// State of a [LexicalDocument]; exposed so the editable layer can reach the
/// block registry.
class LexicalDocumentState extends State<LexicalDocument> {
  late final BlockRegistry _registry = widget.registry ?? BlockRegistry();
  final Map<NodeKey, _CachedBlock> _cache = <NodeKey, _CachedBlock>{};
  List<NodeKey> _topLevelKeys = const [];
  Unsubscribe? _unsubscribe;

  /// The blocks currently mounted.
  BlockRegistry get registry => _registry;

  @override
  void initState() {
    super.initState();
    _attach(widget.editor);
    _refreshTopLevel();
  }

  @override
  void didUpdateWidget(LexicalDocument oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.editor, widget.editor)) {
      _unsubscribe?.call();
      _registry.clear();
      _cache.clear();
      _attach(widget.editor);
      _refreshTopLevel();
    } else if (oldWidget.theme != widget.theme ||
        oldWidget.decoratorBuilders != widget.decoratorBuilders) {
      // Styling is baked into the cached spans, so a theme change invalidates
      // everything. It is a rare event; a finer-grained rule would be more
      // code for no benefit.
      _cache.clear();
    }
  }

  void _attach(LexicalEditor editor) {
    _unsubscribe = editor.registerUpdateListener(_onUpdate);
  }

  void _onUpdate(EditorUpdate update) {
    if (update.isFullReconcile) {
      _cache.clear();
    } else {
      // Marking a node dirty also marks every ancestor, so a dirty descendant
      // always shows up as its containing block being dirty. Invalidating on
      // the union of both sets is therefore exact, not conservative.
      for (final key in update.dirtyElements.keys) {
        _cache.remove(key);
      }
      for (final key in update.dirtyLeaves) {
        _cache.remove(key);
      }
    }
    // A commit can land during a build — see `whenBuildIsDone`. Calling
    // setState from here directly is the mistake this widget would otherwise
    // make on behalf of every application using it.
    whenBuildIsDone(() {
      if (mounted) setState(_refreshTopLevel);
    });
  }

  void _refreshTopLevel() {
    _topLevelKeys = widget.editor.read(
      () => $getRoot().children.map((node) => node.key).toList(),
    );
  }

  @override
  void dispose() {
    _unsubscribe?.call();
    _registry.clear();
    super.dispose();
  }

  // -------------------------------------------------------------------
  // Building
  // -------------------------------------------------------------------

  Widget _topLevelBlock(BuildContext context, int index) {
    final key = _topLevelKeys[index];
    final node = widget.editor.read(() => $getNodeByKey(key));
    if (node == null) return const SizedBox.shrink();

    final cached = _cache[key];
    // Committed states share untouched nodes by reference, so an identity
    // check against the cached version is a sound and very cheap invalidation
    // test — no deep comparison, no versions to track.
    if (cached != null && identical(cached.node, node)) {
      widget.stats?.blocksReused++;
      return cached.widget;
    }

    widget.stats?.blocksBuilt++;
    final built = widget.editor.read(() => _buildNode(context, node, depth: 0));
    _cache[key] = _CachedBlock(node, built, null);
    return built;
  }

  Widget _buildNode(
    BuildContext context,
    LexicalNode node, {
    required int depth,
  }) {
    if (node is DecoratorNode) {
      final builder = widget.decoratorBuilders[node.type];
      if (builder == null) return const SizedBox.shrink();
      return KeyedSubtree(
        key: ValueKey<String>('lexical-block-${node.key.value}'),
        child: builder(context, node),
      );
    }
    if (node is! ElementNode) return const SizedBox.shrink();
    return _buildElement(context, node, depth: depth);
  }

  Widget _buildElement(
    BuildContext context,
    ElementNode element, {
    required int depth,
  }) {
    final theme = widget.theme;
    final style = theme.blockStyleForNode(element);
    final direction = _resolveDirection(element);

    final children = element.children.toList();
    final layout = theme.blockLayouts[element.type];
    final content = layout != null
        ? layout(
            context,
            element,
            (node) => _buildNode(context, node, depth: depth + 1),
          )
        : _buildContent(context, element, children, depth: depth);

    var block = content;

    final markerBuilder = theme.markerBuilders[element.type];
    final marker = markerBuilder?.call(context, element);
    if (marker != null) {
      block = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        textDirection: direction,
        children: [
          SizedBox(
            width: marker.width,
            child: Align(alignment: marker.alignment, child: marker.child),
          ),
          Expanded(child: block),
        ],
      );
    }

    final indent = element.getIndent() * style.indentStep;
    final padding = style.padding.resolve(direction);
    block = Padding(
      padding: EdgeInsets.only(
        left: direction == TextDirection.ltr ? indent : 0,
        right: direction == TextDirection.rtl ? indent : 0,
      ).add(padding),
      child: block,
    );

    if (style.decoration != null) {
      block = DecoratedBox(decoration: style.decoration!, child: block);
    }
    if (style.spacing > 0 && depth == 0) {
      block = Padding(
        padding: EdgeInsets.only(bottom: style.spacing),
        child: block,
      );
    }
    return KeyedSubtree(
      key: ValueKey<String>('lexical-block-${element.key.value}'),
      child: block,
    );
  }

  Widget _buildContent(
    BuildContext context,
    ElementNode element,
    List<LexicalNode> children, {
    required int depth,
  }) {
    final direction = _resolveDirection(element);
    final align = _resolveAlign(element, direction);
    final scaler = widget.textScaler ?? MediaQuery.textScalerOf(context);

    // Two genuinely different cases, kept distinct rather than unified: a
    // block whose children are inline lays out one text run, and a block
    // whose children are elements lays out child blocks. An over-general
    // design collapses exactly where the two meet.
    Widget inlineBlock() {
      final built = SpanBuilder(
        theme: widget.theme,
        context: context,
        decoratorBuilders: widget.decoratorBuilders,
      ).buildBlock(element);
      return RegisteredBlock(
        nodeKey: element.key,
        offsets: built.offsets,
        child: LexicalInlineBlock(
          span: built.span,
          textDirection: direction,
          textAlign: align,
          textScaler: scaler,
        ),
      );
    }

    final blockChildren = children.where((child) => !isInlineContent(child));
    if (blockChildren.isEmpty) {
      // Also covers the empty block, which still needs a line's height or
      // the caret has nowhere to go.
      return inlineBlock();
    }

    final parts = <Widget>[
      // The span builder skips block children, so this is exactly the inline
      // content — present only in the degenerate mixed case.
      if (children.any(isInlineContent)) inlineBlock(),
      for (final child in blockChildren)
        _buildNode(context, child, depth: depth + 1),
    ];
    if (parts.length == 1) return parts.first;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: parts,
    );
  }

  TextDirection _resolveDirection(ElementNode element) {
    final declared = element.getDirection();
    if (declared != null) {
      return declared == NodeDirection.rtl
          ? TextDirection.rtl
          : TextDirection.ltr;
    }
    return widget.textDirection ??
        Directionality.maybeOf(context) ??
        TextDirection.ltr;
  }

  TextAlign _resolveAlign(ElementNode element, TextDirection direction) {
    final style = widget.theme.blockStyleForNode(element);
    return switch (element.getFormat()) {
      ElementFormat.left => TextAlign.left,
      ElementFormat.center => TextAlign.center,
      ElementFormat.right => TextAlign.right,
      ElementFormat.justify => TextAlign.justify,
      // start and end are logical: they resolve against the block's own
      // direction, which is why the model keeps them symbolic.
      ElementFormat.start => TextAlign.start,
      ElementFormat.end => TextAlign.end,
      ElementFormat.none => style.align ?? TextAlign.start,
    };
  }

  @override
  Widget build(BuildContext context) {
    final direction =
        widget.textDirection ??
        Directionality.maybeOf(context) ??
        TextDirection.ltr;

    final Widget body;
    if (widget.scrollable) {
      body = ListView.builder(
        controller: widget.scrollController,
        padding: widget.padding,
        itemCount: _topLevelKeys.length,
        // Estimated from measured children, which keeps the scrollbar stable
        // without measuring the whole document up front.
        itemBuilder: _topLevelBlock,
      );
    } else {
      body = Padding(
        padding: widget.padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < _topLevelKeys.length; i++)
              _topLevelBlock(context, i),
          ],
        ),
      );
    }

    final interaction = widget.interaction;
    return Directionality(
      textDirection: direction,
      child: BlockRegistryScope(
        registry: _registry,
        child: interaction == null
            ? body
            : LexicalInteractionRegion(
                editor: widget.editor,
                registry: _registry,
                interaction: interaction,
                child: body,
              ),
      ),
    );
  }
}
