/// The `.lexical` file format for `lexical_core`.
///
/// A `.lexical` file is an editor state with four fields around it, and this
/// package is that envelope — the Dart counterpart of `@lexical/file`. Reading
/// and writing the bytes is left to the application: `dart:io` on a server,
/// `file_selector` or a share sheet on a device, a download link on the web.
///
/// ```dart
/// // Save.
/// final document = serializedDocumentFromEditorState(
///   editor.editorState,
///   source: 'Hinata',
/// );
/// await File(suggestedDocumentFileName()).writeAsString(document.encode());
///
/// // Open.
/// final opened = SerializedDocument.parse(await file.readAsString());
/// editor.setEditorState(
///   editorStateFromSerializedDocument(editor, opened),
/// );
/// ```
///
/// Parsing and installing are two steps on purpose: a file that turns out to
/// be corrupt should leave the document the user already has open untouched.
///
/// The format is the one the Lexical playground's *Import* and *Export*
/// buttons read and write, so a file saved here opens on the web and the other
/// way round — provided both sides know every node type in it. Types the
/// editor does not know follow its `UnknownNodePolicy`, which is the setting
/// that decides whether an older client can still open a newer document.
library;

export 'src/serialized_document.dart'
    show
        SerializedDocument,
        defaultDocumentSource,
        editorStateFromSerializedDocument,
        lexicalCompatibleVersion,
        serializedDocumentFromEditorState,
        suggestedDocumentFileName;
