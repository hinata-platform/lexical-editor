// Run it with:  dart run example/main.dart
//
// Saving and opening a .lexical file — the format the Lexical playground's
// Import and Export buttons use. Everything here is pure data: this program
// never touches the disk, because where the bytes go is the application's
// decision and differs on every platform.
import 'package:lexical_core/lexical_core.dart';
import 'package:lexical_file/lexical_file.dart';

void main() {
  // 1. Save ---------------------------------------------------------------
  final editor = LexicalEditor();
  editor.update(() {
    $getRoot()
      ..clear()
      ..append($createParagraphNode()..append($createTextNode('Hallo Welt')));
  }, discrete: true);

  final document = serializedDocumentFromEditorState(
    editor.editorState,
    source: 'lexical_file example',
    // Left out in real code; fixed here so the output is the same every run.
    lastSaved: DateTime.utc(2026, 7, 26, 12),
  );

  print('File name: ${suggestedDocumentFileName(document.lastSavedAt)}');
  print('Contents:  ${document.encode()}\n');

  // 2. Open ---------------------------------------------------------------
  final opened = SerializedDocument.parse(document.encode());
  print('Written by ${opened.source}, Lexical ${opened.version},');
  print('last saved ${opened.lastSavedAt.toIso8601String()}.');

  final reader = LexicalEditor();
  reader.setEditorState(editorStateFromSerializedDocument(reader, opened));
  print('Text:      "${reader.read(() => $getRoot().getTextContent())}"\n');

  // 3. A file that is not one ---------------------------------------------
  // Parsing and installing are separate steps so that this leaves the
  // document already open exactly as it was.
  try {
    SerializedDocument.parse('{"source":"someone else"}');
  } on MalformedDocumentException catch (error) {
    print('Refused:   ${error.message}');
  }
  print('Still open: "${reader.read(() => $getRoot().getTextContent())}"');
}
