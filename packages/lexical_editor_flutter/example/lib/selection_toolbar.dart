// A format toolbar that follows the selection, and the link editor it opens.
//
// Both are application code on purpose. The packages expose the geometry —
// `LexicalEditableState.selectionRects` — and the operations —
// `formatTextCommand`, `toggleLinkCommand` — and leave the chrome to whoever
// owns the design system. This file is what that looks like in practice, and
// it is about a hundred lines.
import 'package:flutter/material.dart';
import 'package:lexical_editor_flutter/lexical_editor_flutter.dart';

/// Shows a floating toolbar whenever [editor] has a non-empty selection.
class SelectionToolbar extends StatefulWidget {
  const SelectionToolbar({
    required this.editor,
    required this.editableKey,
    required this.child,
    super.key,
    this.onComment,
  });

  /// Called when the comment button is pressed, if one is wanted.
  final VoidCallback? onComment;

  final LexicalEditor editor;

  /// The key on the editable, for reaching the selection's geometry.
  final GlobalKey<LexicalEditableState> editableKey;

  final Widget child;

  @override
  State<SelectionToolbar> createState() => _SelectionToolbarState();
}

class _SelectionToolbarState extends State<SelectionToolbar> {
  OverlayEntry? _entry;
  Unsubscribe? _unsubscribe;
  bool _editingLink = false;

  @override
  void initState() {
    super.initState();
    _unsubscribe = widget.editor.registerUpdateListener((_) => _schedule());
  }

  @override
  void dispose() {
    _unsubscribe?.call();
    _entry?.remove();
    super.dispose();
  }

  /// Geometry only exists after layout, and a commit can land *during* a
  /// build — so the toolbar is always updated at the end of the frame.
  void _schedule() {
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
  }

  /// The selection's bounds, or `null` when there is no selection.
  ///
  /// Read afresh every time rather than cached: blocks register their render
  /// objects in a post-frame callback, so the first answer after a commit can
  /// be a frame stale — and a toolbar that lands 80 pixels below the words it
  /// belongs to is the visible result.
  Rect? get _anchor {
    final rects = widget.editableKey.currentState?.selectionRects ?? const [];
    if (rects.isEmpty) return null;
    return rects.reduce((a, b) => a.expandToInclude(b));
  }

  void _sync() {
    if (!mounted) return;
    if (_anchor == null) {
      _hide();
      return;
    }
    if (_entry == null) {
      _entry = OverlayEntry(builder: _buildOverlay);
      Overlay.of(context).insert(_entry!);
    } else {
      // The selection can move without changing whether there is one, and the
      // active-format highlighting changes with every commit.
      _entry!.markNeedsBuild();
    }
  }

  void _hide() {
    if (_entry == null) return;
    _entry!.remove();
    _entry = null;
    _editingLink = false;
  }

  // -------------------------------------------------------------------
  // Reading the selection
  // -------------------------------------------------------------------

  /// Whether every text node in the selection carries [format].
  ///
  /// The whole selection, not the first node: a toolbar that lights up "bold"
  /// because the selection *starts* in bold text lies about what a second
  /// press will do.
  bool _isActive(TextFormat format) => widget.editor.read(() {
    final selection = $getSelection();
    if (selection is! RangeSelection) return false;
    if (selection.isCollapsed) {
      return selection.format & format.bit == format.bit;
    }
    final texts = selection.getNodes().whereType<TextNode>();
    return texts.isNotEmpty && texts.every((node) => node.hasFormat(format));
  });

  String? get _currentLink =>
      widget.editor.read(() => $getLinkAtSelection()?.url);

  // -------------------------------------------------------------------
  // Acting on it
  // -------------------------------------------------------------------

  void _format(TextFormat format) =>
      widget.editor.dispatchCommand(formatTextCommand, format);

  void _applyLink(String? url) {
    widget.editor.dispatchCommand(toggleLinkCommand, url);
    setState(() => _editingLink = false);
    _entry?.markNeedsBuild();
    // The link field took focus; give it back so typing continues.
    widget.editableKey.currentState?.requestFocus();
  }

  // -------------------------------------------------------------------
  // Chrome
  // -------------------------------------------------------------------

  @override
  Widget build(BuildContext context) =>
      NotificationListener<ScrollNotification>(
        // A toolbar that stays put while the text scrolls out from under it is
        // worse than no toolbar.
        onNotification: (_) {
          _sync();
          return false;
        },
        child: widget.child,
      );

  Widget _buildOverlay(BuildContext context) {
    final anchor = _anchor;
    if (anchor == null) return const SizedBox.shrink();
    return Positioned.fill(
      // Centring on the selection with a fixed offset is not enough: a word
      // near the left edge puts half the toolbar off-screen, where it is
      // clipped and unreachable. The position has to be computed from the
      // toolbar's measured size, which is what this delegate is for.
      child: CustomSingleChildLayout(
        delegate: _ToolbarLayout(anchor),
        child: Material(
          elevation: 6,
          borderRadius: BorderRadius.circular(10),
          child: _editingLink
              ? _LinkField(
                  initial: _currentLink ?? 'https://',
                  onDone: _applyLink,
                )
              : _formatRow(context),
        ),
      ),
    );
  }

  Widget _formatRow(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget button(
      IconData icon,
      String tooltip,
      VoidCallback onTap, {
      bool active = false,
    }) => IconButton(
      tooltip: tooltip,
      onPressed: onTap,
      isSelected: active,
      iconSize: 18,
      visualDensity: VisualDensity.compact,
      icon: Icon(icon, color: active ? scheme.primary : null),
    );

    // The buttons must not take focus: the editor would lose the selection
    // they are about to act on, and on a phone the keyboard would drop.
    return ExcludeFocus(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (icon, tooltip, format) in const [
              (Icons.format_bold, 'Fett', TextFormat.bold),
              (Icons.format_italic, 'Kursiv', TextFormat.italic),
              (Icons.format_underlined, 'Unterstrichen', TextFormat.underline),
              (
                Icons.strikethrough_s,
                'Durchgestrichen',
                TextFormat.strikethrough,
              ),
              (Icons.code, 'Code', TextFormat.code),
            ])
              button(
                icon,
                tooltip,
                () => _format(format),
                active: _isActive(format),
              ),
            // A bare VerticalDivider has no height of its own and stretches
            // to whatever it is offered — which in a loosely constrained
            // overlay is the whole screen, taking the toolbar with it.
            const SizedBox(height: 24, child: VerticalDivider(width: 9)),
            button(Icons.link, 'Link', () {
              setState(() => _editingLink = true);
              _entry?.markNeedsBuild();
            }, active: _currentLink != null),
            if (_currentLink != null)
              button(Icons.link_off, 'Link entfernen', () => _applyLink(null)),
            if (widget.onComment != null)
              button(Icons.add_comment_outlined, 'Kommentieren', () {
                widget.onComment!();
                _hide();
              }),
          ],
        ),
      ),
    );
  }
}

/// Places the toolbar over [anchor] without letting it leave the screen.
class _ToolbarLayout extends SingleChildLayoutDelegate {
  const _ToolbarLayout(this.anchor);

  /// The selection, in the overlay's coordinates.
  final Rect anchor;

  static const double _margin = 8;
  static const double _gap = 10;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      constraints.loosen().copyWith(
        maxWidth: constraints.maxWidth - _margin * 2,
      );

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final x = (anchor.center.dx - childSize.width / 2).clamp(
      _margin,
      // A toolbar wider than the screen would produce an empty range; the max
      // is pinned to at least the margin so the clamp stays valid.
      (size.width - childSize.width - _margin).clamp(_margin, double.infinity),
    );
    // Above the selection when there is room, below it otherwise — a toolbar
    // covering the text it acts on is worse than one on the wrong side.
    final above = anchor.top - childSize.height - _gap >= _margin;
    final y = above
        ? anchor.top - childSize.height - _gap
        : (anchor.bottom + _gap).clamp(
            _margin,
            (size.height - childSize.height - _margin).clamp(
              _margin,
              double.infinity,
            ),
          );
    return Offset(x, y);
  }

  @override
  bool shouldRelayout(_ToolbarLayout oldDelegate) =>
      oldDelegate.anchor != anchor;
}

/// The URL field the link button opens.
class _LinkField extends StatefulWidget {
  const _LinkField({required this.initial, required this.onDone});

  final String initial;

  /// Called with the URL, or `null` to unlink. Not called on cancel.
  final ValueChanged<String?> onDone;

  @override
  State<_LinkField> createState() => _LinkFieldState();
}

class _LinkFieldState extends State<_LinkField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
  );
  bool _unsafe = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final url = _controller.text.trim();
    // The model stores a URL verbatim so documents round-trip; refusing an
    // unsafe one is the *application's* job, at the point it is created.
    // `javascript:` in a document is a stored XSS waiting for a tap.
    if (!isSafeUrl(url)) {
      setState(() => _unsafe = true);
      return;
    }
    widget.onDone(url);
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 260,
          child: TextField(
            controller: _controller,
            autofocus: true,
            decoration: InputDecoration(
              isDense: true,
              border: InputBorder.none,
              hintText: 'https://…',
              errorText: _unsafe ? 'Kein erlaubtes Schema' : null,
            ),
            onChanged: (_) {
              if (_unsafe) setState(() => _unsafe = false);
            },
            onSubmitted: (_) => _submit(),
          ),
        ),
        IconButton(
          tooltip: 'Übernehmen',
          onPressed: _submit,
          icon: const Icon(Icons.check_circle, size: 20),
        ),
      ],
    ),
  );
}
