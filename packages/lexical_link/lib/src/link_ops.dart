/// Making, editing and removing links from a selection.
library;

import 'package:lexical_core/lexical_core.dart';

import 'link_node.dart';

/// Wraps the selection in a link, retargets the one it is in, or removes it.
///
/// Dispatch with the URL to link, or `null` to unlink:
///
/// ```dart
/// editor.dispatchCommand(toggleLinkCommand, 'https://lexical.dev');
/// editor.dispatchCommand(toggleLinkCommand, null);   // unlink
/// ```
const LexicalCommand<String?> toggleLinkCommand = LexicalCommand('TOGGLE_LINK');

/// Registers [toggleLinkCommand] and the empty-link cleanup on [editor].
///
/// The cleanup is not housekeeping. A link with no children renders nothing,
/// so an anchor left behind by deleting the text inside it is *invisible*: it
/// is saved, sent to every other client, exported to markdown as `[](url)`,
/// and it accumulates — one per edit that emptied a link. Upstream removes it
/// in the same place, for the same reason.
Unsubscribe registerLink(LexicalEditor editor) {
  final unsubscribers = [
    editor.registerCommand<String?>(toggleLinkCommand, (url) {
      $toggleLink(url);
      return true;
    }, CommandPriority.editor),
    for (final type in const ['link', 'autolink'])
      editor.registerNodeTransform(type, (node) {
        if (node is! LinkNode || node.canBeEmpty || !node.isEmpty) return;
        final parent = node.getParent();
        node.remove();
        // A paragraph that held nothing but the link is not empty on purpose
        // either — but the root's last child is, and removing it would leave
        // a document with nowhere to type.
        if (parent != null && parent.isEmpty && parent.isInline) {
          parent.remove();
        }
      }),
  ];
  return () {
    for (final unsubscribe in unsubscribers) {
      unsubscribe();
    }
  };
}

/// The link the selection sits in, or `null`.
///
/// What a link editor needs in order to open with the current URL filled in
/// rather than empty. It answers for a **caret** too, which is the case that
/// matters: someone clicking inside link text expects to edit that link, not
/// to make a new one.
LinkNode? $getLinkAtSelection() {
  final selection = $getSelection();
  if (selection is! RangeSelection) return null;
  final first = _enclosingLink(selection.anchor.getNode());
  if (first == null) return null;
  if (selection.isCollapsed) return first;
  for (final node in selection.getNodes()) {
    if (node is LinkNode) continue;
    if (_enclosingLink(node)?.key != first.key) return null;
  }
  return first;
}

/// Links the selection to [url], or unlinks it when [url] is `null`.
///
/// Four cases, and they are genuinely different:
///
/// * **Inside a link already** — the link is retargeted. Selecting part of a
///   link's text and giving a new URL changes that link; splitting it into two
///   links with different targets is never what the gesture meant.
/// * **`null`** — every link the selection touches is unwrapped, its children
///   left in place. Unlinking must not delete the text.
/// * **A collapsed caret outside a link** — nothing happens. There is no text
///   to link, and inserting the URL as text is a different command.
/// * **A range** — the boundary text nodes are split so the link covers
///   exactly what was selected, links already inside the range are unwrapped
///   so the result is one link rather than nested ones, and each run of
///   siblings is wrapped where it sits. A selection crossing a paragraph
///   boundary therefore produces one link per paragraph: an element cannot
///   span two parents, and the alternative — silently linking only the first
///   — loses half the gesture.
///
/// The URL is stored **verbatim**, as everything in this package is, so
/// documents round-trip unchanged. Validate with [isSafeUrl] before making it
/// tappable — see the note in the library docs.
void $toggleLink(String? url, {String? rel, String? target, String? title}) {
  final selection = $getSelection();
  if (selection is! RangeSelection) return;

  final existing = $getLinkAtSelection();
  if (existing != null) {
    if (url == null) {
      _unwrap(existing);
      return;
    }
    existing.setUrl(url);
    if (rel != null) existing.setRel(rel);
    if (target != null) existing.setTarget(target);
    if (title != null) existing.setTitle(title);
    return;
  }

  if (url == null) {
    for (final link in _linksTouching(selection)) {
      _unwrap(link);
    }
    return;
  }

  if (selection.isCollapsed) return;

  final runs = _selectedRuns(selection);
  for (final run in runs) {
    // A link inside the new link would render as one and serialize as two.
    for (final node in run) {
      final inner = _enclosingLink(node);
      if (inner != null) _unwrap(inner);
    }
  }

  for (final run in _selectedRuns(selection)) {
    if (run.isEmpty) continue;
    final link = $createLinkNode(url, rel: rel, target: target, title: title);
    run.first.insertBefore(link);
    for (final node in run) {
      link.append(node);
    }
  }
}

/// The nearest link ancestor of [node], itself included.
LinkNode? _enclosingLink(LexicalNode? node) {
  var current = node;
  while (current != null) {
    if (current is LinkNode) return current;
    current = current.getParent();
  }
  return null;
}

Set<LinkNode> _linksTouching(RangeSelection selection) {
  final links = <NodeKey, LinkNode>{};
  for (final node in selection.getNodes()) {
    final link = _enclosingLink(node);
    if (link != null) links[link.key] = link;
  }
  return links.values.toSet();
}

/// Replaces [link] with its children, keeping the text where it was.
void _unwrap(LinkNode link) {
  final children = link.children.toList();
  for (final child in children) {
    link.insertBefore(child);
  }
  link.remove();
}

/// The selected text nodes, split at the selection's edges and grouped into
/// runs of siblings.
///
/// Splitting has to happen before anything is wrapped: a link that starts
/// halfway through a text node would otherwise take the whole node with it.
List<List<TextNode>> _selectedRuns(RangeSelection selection) {
  final (start, end) = selection.orderedPoints;
  final startNode = start.getNode();
  final endNode = end.getNode();
  if (startNode is! TextNode || endNode is! TextNode) {
    return _group(selection.getNodes().whereType<TextNode>().toList());
  }

  if (start.key == end.key) {
    final size = startNode.getTextContentSize();
    var target = startNode;
    if (start.offset > 0 || end.offset < size) {
      final parts = startNode.splitText([start.offset, end.offset]);
      target = start.offset > 0 ? parts[1] : parts[0];
    }
    selection.anchor.set(target.key, 0, PointType.text);
    selection.focus.set(
      target.key,
      target.getTextContentSize(),
      PointType.text,
    );
    return [
      [target],
    ];
  }

  // The end first: splitting the start node would otherwise invalidate an
  // offset into the same node — and they are only the same node in the branch
  // above, but the order costs nothing and the rule is easy to get wrong.
  var last = endNode;
  if (end.offset > 0 && end.offset < endNode.getTextContentSize()) {
    last = endNode.splitText([end.offset])[0];
  }
  var first = startNode;
  if (start.offset > 0 && start.offset < startNode.getTextContentSize()) {
    first = startNode.splitText([start.offset])[1];
  }

  // Re-anchoring on whole nodes lets the core's own walk enumerate the range,
  // rather than this package growing a second tree traversal to maintain.
  selection.anchor.set(first.key, 0, PointType.text);
  selection.focus.set(last.key, last.getTextContentSize(), PointType.text);
  return _group(selection.getNodes().whereType<TextNode>().toList());
}

/// Splits [nodes] into runs that share a parent and sit next to each other.
List<List<TextNode>> _group(List<TextNode> nodes) {
  final runs = <List<TextNode>>[];
  for (final node in nodes) {
    final parent = node.getParent();
    if (parent == null) continue;
    final run = runs.isEmpty ? null : runs.last;
    if (run != null &&
        run.last.getParent()?.key == parent.key &&
        run.last.getNextSibling()?.key == node.key) {
      run.add(node);
    } else {
      runs.add([node]);
    }
  }
  return runs;
}
