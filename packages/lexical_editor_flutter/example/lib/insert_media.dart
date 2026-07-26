// Inserting an image or a video, and the one thing that makes the difference
// between them worth knowing:
//
//   an image is *any* URL, a video is only one Lexical can embed.
//
// Lexical has no generic video node — the whole list is YouTube, Twitter and
// Figma — so this dialog asks matchEmbedUrl what it is looking at and says so
// before anything is inserted. A Vimeo link is not a failure of this package;
// it is a link, and the honest thing is to tell the user that.
import 'package:flutter/material.dart';
import 'package:lexical_editor_flutter/lexical_editor_flutter.dart';

/// Asks for an image and inserts it.
Future<void> showInsertImageDialog(
  BuildContext context,
  LexicalEditor editor,
) async {
  final result = await showDialog<_ImageInput>(
    context: context,
    builder: (context) => const _ImageDialog(),
  );
  if (result == null) return;
  editor.dispatchCommand(
    insertImageCommand,
    ImageAttributes(
      src: result.src,
      altText: result.altText,
      caption: result.caption.isEmpty ? null : result.caption,
    ),
  );
}

/// Asks for a media URL and inserts it, or reports that it is not embeddable.
Future<void> showInsertEmbedDialog(
  BuildContext context,
  LexicalEditor editor,
) async {
  final url = await showDialog<String>(
    context: context,
    builder: (context) => const _EmbedDialog(),
  );
  if (url == null) return;

  final handled = editor.dispatchCommand(insertEmbedFromUrlCommand, url);
  if (handled || !context.mounted) return;

  // Nothing embedded it, so it stays what it always was: a link.
  editor.dispatchCommand(toggleLinkCommand, url);
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text(
        'Lexical only embeds YouTube, tweets and Figma — '
        'this became a link.',
      ),
    ),
  );
}

class _ImageInput {
  const _ImageInput({
    required this.src,
    required this.altText,
    required this.caption,
  });

  final String src;
  final String altText;
  final String caption;
}

class _ImageDialog extends StatefulWidget {
  const _ImageDialog();

  @override
  State<_ImageDialog> createState() => _ImageDialogState();
}

class _ImageDialogState extends State<_ImageDialog> {
  final _src = TextEditingController(
    text: 'https://picsum.photos/seed/lexical/900/600',
  );
  final _alt = TextEditingController(text: 'An image');
  final _caption = TextEditingController();

  @override
  void dispose() {
    _src.dispose();
    _alt.dispose();
    _caption.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Insert an image'),
    content: SizedBox(
      width: 420,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _src,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Address',
              helperText: 'https:, data: or an asset path. GIFs too.',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _alt,
            decoration: const InputDecoration(labelText: 'Alt text'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _caption,
            decoration: const InputDecoration(labelText: 'Caption (optional)'),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(
          context,
          _ImageInput(
            src: _src.text.trim(),
            altText: _alt.text.trim(),
            caption: _caption.text.trim(),
          ),
        ),
        child: const Text('Insert'),
      ),
    ],
  );
}

class _EmbedDialog extends StatefulWidget {
  const _EmbedDialog();

  @override
  State<_EmbedDialog> createState() => _EmbedDialogState();
}

class _EmbedDialogState extends State<_EmbedDialog> {
  final _url = TextEditingController(
    text: 'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
  );

  @override
  void initState() {
    super.initState();
    // The verdict updates while typing, so the rule is visible rather than
    // something the user discovers by pressing the button.
    _url.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final target = matchEmbedUrl(_url.text);
    final verdict = switch (target?.kind) {
      EmbedKind.youtube => 'YouTube video · ${target!.id}',
      EmbedKind.tweet => 'Tweet · ${target!.id}',
      EmbedKind.figma => 'Figma · ${target!.id}',
      null => 'Not embeddable — this becomes a link.',
    };

    return AlertDialog(
      title: const Text('Embed media'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _url,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Address',
                helperText: 'YouTube, Twitter/X or Figma.',
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(
                  target == null ? Icons.link : Icons.play_circle_outline,
                  size: 18,
                  color: Theme.of(context).colorScheme.outline,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    verdict,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _url.text.trim()),
          child: const Text('Insert'),
        ),
      ],
    );
  }
}
