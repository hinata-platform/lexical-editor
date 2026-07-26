/// Rebuilding a widget when the document changes.
library;

import 'package:flutter/widgets.dart';
import 'package:lexical_core/lexical_core.dart';

import 'build_phase.dart';

/// Builds a widget from the editor's current state, after every commit.
///
/// For everything *around* the document — a word count, a toolbar's active
/// formats, a preview pane, a save indicator.
///
/// ```dart
/// LexicalBuilder(
///   editor: editor,
///   builder: (context, state, _) => Text('${state.root.getTextContent()}'),
/// )
/// ```
///
/// ## Why not just listen and call setState
///
/// Because a commit can land **during a build**, and `setState` then throws.
/// It is not an exotic case: registering behaviour, seeding an empty document
/// and reading `editorState` all commit, and all three happen in `initState`
/// — which runs inside a build. An application that writes the obvious
/// `editor.registerUpdateListener((_) => setState(() {}))` hits it on the
/// first frame.
///
/// This widget defers that rebuild to the end of the frame instead.
class LexicalBuilder extends StatefulWidget {
  /// Rebuilds [builder] whenever [editor] commits.
  const LexicalBuilder({
    required this.editor,
    required this.builder,
    super.key,
    this.child,
  });

  /// The editor to watch.
  final LexicalEditor editor;

  /// Builds the widget from the committed state.
  ///
  /// [child] is passed through untouched, for the part of the subtree that
  /// does not depend on the document and should not be rebuilt with it.
  final Widget Function(BuildContext context, EditorState state, Widget? child)
  builder;

  /// A subtree that does not depend on the document.
  final Widget? child;

  @override
  State<LexicalBuilder> createState() => _LexicalBuilderState();
}

class _LexicalBuilderState extends State<LexicalBuilder> {
  Unsubscribe? _unsubscribe;
  bool _rebuildScheduled = false;

  @override
  void initState() {
    super.initState();
    _unsubscribe = widget.editor.registerUpdateListener(_onCommit);
  }

  @override
  void didUpdateWidget(LexicalBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.editor, widget.editor)) return;
    _unsubscribe?.call();
    _unsubscribe = widget.editor.registerUpdateListener(_onCommit);
  }

  @override
  void dispose() {
    _unsubscribe?.call();
    super.dispose();
  }

  void _onCommit(EditorUpdate update) {
    if (!isBuildingWidgets) {
      setState(() {});
      return;
    }
    // Mid-build. Rebuild at the end of the frame instead, once — several
    // commits in one frame are one rebuild, which is what you want anyway.
    if (_rebuildScheduled) return;
    _rebuildScheduled = true;
    whenBuildIsDone(() {
      _rebuildScheduled = false;
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) =>
      widget.builder(context, widget.editor.editorState, widget.child);
}
