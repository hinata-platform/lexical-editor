// Comments on a selection, in a sidebar, with replies.
//
// The split is the whole idea: the **document** records only that a range is
// annotated, as a mark carrying an id. Everything the comment says — author,
// text, time, replies — lives here, outside the document, keyed by that id.
//
// That is what lets a comment be written, answered and resolved without
// touching the document, and what keeps a document with fifty comment threads
// the same size as one with none. It is also how the quoted text stays
// correct: the sidebar asks the document what the mark covers *now*, so
// editing the sentence updates the quote instead of stranding it.
import 'package:flutter/material.dart';
import 'package:lexical_editor_flutter/lexical_editor_flutter.dart';

import 'app_theme.dart';

/// One message in a thread.
class Comment {
  const Comment({required this.author, required this.text, required this.at});

  final String author;
  final String text;
  final DateTime at;
}

/// A thread, identified by the mark id it belongs to.
class CommentThread {
  CommentThread(this.id);

  final String id;
  final List<Comment> comments = [];

  /// A thread with nothing in it yet — the composer is open on it.
  bool get isDraft => comments.isEmpty;
}

/// The threads of one document.
///
/// A plain [ChangeNotifier]: an application would put them in whatever it
/// already uses, and send them to a server. Nothing here knows about Lexical.
class CommentStore extends ChangeNotifier {
  final List<CommentThread> _threads = [];
  int _counter = 0;

  List<CommentThread> get threads => List.unmodifiable(_threads);

  /// The thread the composer is currently open on.
  String? get draftId => _threads.where((t) => t.isDraft).firstOrNull?.id;

  /// Starts a thread and returns its id, which becomes the mark's id.
  String startThread() {
    final id = 'comment-${++_counter}';
    _threads.add(CommentThread(id));
    notifyListeners();
    return id;
  }

  void addComment(String id, String author, String text) {
    final thread = _threads.where((t) => t.id == id).firstOrNull;
    if (thread == null) return;
    thread.comments.add(
      Comment(author: author, text: text, at: DateTime.now()),
    );
    notifyListeners();
  }

  void removeThread(String id) {
    _threads.removeWhere((thread) => thread.id == id);
    notifyListeners();
  }
}

/// The sidebar: one card per thread, quote on top, replies below.
class CommentsPanel extends StatelessWidget {
  const CommentsPanel({
    required this.editor,
    required this.store,
    required this.author,
    super.key,
  });

  final LexicalEditor editor;
  final CommentStore store;
  final String author;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) {
      if (store.threads.isEmpty) {
        return const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Select some text and tap the comment icon.',
              textAlign: TextAlign.center,
            ),
          ),
        );
      }
      return ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: store.threads.length,
        itemBuilder: (context, index) {
          final thread = store.threads[index];
          return _ThreadCard(
            thread: thread,
            // Read from the document, not stored with the comment: the quote
            // follows the text as it is edited.
            quote: editor.read(() => $getMarkedText(thread.id)),
            onSubmit: (text) => store.addComment(thread.id, author, text),
            onResolve: () {
              editor.dispatchCommand(removeMarkCommand, thread.id);
              store.removeThread(thread.id);
            },
          );
        },
      );
    },
  );
}

class _ThreadCard extends StatelessWidget {
  const _ThreadCard({
    required this.thread,
    required this.quote,
    required this.onSubmit,
    required this.onResolve,
  });

  final CommentThread thread;
  final String quote;
  final ValueChanged<String> onSubmit;
  final VoidCallback onResolve;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Palette.surface,
        borderRadius: Radii.control,
        border: Border.all(color: Palette.line),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Palette.accent.withValues(alpha: 0.09),
                      borderRadius: const BorderRadius.all(Radius.circular(4)),
                    ),
                    child: Text(
                      quote.isEmpty ? '(text deleted)' : quote,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelLarge,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Resolve',
                  iconSize: 18,
                  onPressed: onResolve,
                  icon: const Icon(Icons.check),
                ),
              ],
            ),
            for (final comment in thread.comments)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(comment.author, style: theme.textTheme.labelMedium),
                    Text(comment.text, style: theme.textTheme.bodyMedium),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            _Composer(
              hint: thread.isDraft ? 'Comment…' : 'Reply…',
              autofocus: thread.isDraft,
              onSubmit: onSubmit,
            ),
          ],
        ),
      ),
    );
  }
}

class _Composer extends StatefulWidget {
  const _Composer({
    required this.hint,
    required this.autofocus,
    required this.onSubmit,
  });

  final String hint;
  final bool autofocus;
  final ValueChanged<String> onSubmit;

  @override
  State<_Composer> createState() => _ComposerState();
}

class _ComposerState extends State<_Composer> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    widget.onSubmit(text);
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: TextField(
          controller: _controller,
          autofocus: widget.autofocus,
          decoration: InputDecoration(
            isDense: true,
            hintText: widget.hint,
            filled: true,
            fillColor: Palette.bar,
            border: const OutlineInputBorder(
              borderRadius: Radii.control,
              borderSide: BorderSide(color: Palette.line),
            ),
            enabledBorder: const OutlineInputBorder(
              borderRadius: Radii.control,
              borderSide: BorderSide(color: Palette.line),
            ),
          ),
          onSubmitted: (_) => _submit(),
        ),
      ),
      IconButton(onPressed: _submit, icon: const Icon(Icons.send, size: 18)),
    ],
  );
}
