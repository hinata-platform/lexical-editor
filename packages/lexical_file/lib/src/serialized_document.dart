/// The `.lexical` envelope: an editor state plus the little that surrounds it.
library;

import 'dart:convert';

import 'package:lexical_core/lexical_core.dart';
import 'package:meta/meta.dart';

/// The Lexical version whose wire format these packages implement.
///
/// Written into every document as [SerializedDocument.version], because that
/// is the field upstream fills with the running `lexical` package version. No
/// importer is known to *act* on it — it exists so a file can be diagnosed
/// years later, which is reason enough to fill it in truthfully.
const String lexicalCompatibleVersion = '0.48.0';

/// What upstream writes when no application names itself.
const String defaultDocumentSource = 'Lexical';

/// A document as it is stored in a `.lexical` file.
///
/// ```json
/// { "editorState": { "root": … },
///   "lastSaved": 1753488000000,
///   "source": "Lexical",
///   "version": "0.48.0" }
/// ```
///
/// This is `SerializedDocument` from `@lexical/file`, field for field. That
/// package also contains the browser half — a download link and a file input —
/// which has no counterpart here, so this port is only the data: reading and
/// writing bytes is the application's job, and on Flutter it differs per
/// platform anyway.
///
/// The editor state is held as **decoded JSON**, not as a string. Keeping it
/// as a map is what lets a caller inspect or migrate a document without
/// constructing an editor, and it removes any chance of the envelope and its
/// contents disagreeing about escaping.
@immutable
final class SerializedDocument {
  /// Creates a document envelope around [editorState].
  const SerializedDocument({
    required this.editorState,
    required this.lastSaved,
    this.source = defaultDocumentSource,
    this.version = lexicalCompatibleVersion,
  });

  /// The serialized editor state — the same map [EditorState.toJson] returns.
  final Map<String, Object?> editorState;

  /// When the document was last written, in milliseconds since the epoch, UTC.
  final int lastSaved;

  /// What wrote it. Free text; upstream leaves it at [defaultDocumentSource].
  final String source;

  /// The Lexical version that wrote it.
  final String version;

  /// [lastSaved] as a point in time.
  DateTime get lastSavedAt =>
      DateTime.fromMillisecondsSinceEpoch(lastSaved, isUtc: true);

  /// Reads an envelope from decoded JSON.
  ///
  /// Only `editorState` is required. Everything else is metadata about the
  /// writer, and a file that lost it is still a document — refusing to open it
  /// would trade a user's work for a field nothing reads.
  factory SerializedDocument.fromJson(Map<String, Object?> json) {
    final state = json['editorState'];
    if (state is! Map<String, Object?>) {
      throw const MalformedDocumentException(
        'A .lexical document needs an "editorState" object.',
      );
    }
    final lastSaved = json['lastSaved'];
    final source = json['source'];
    final version = json['version'];
    return SerializedDocument(
      editorState: state,
      lastSaved: lastSaved is int
          ? lastSaved
          : (lastSaved is num ? lastSaved.toInt() : 0),
      source: source is String ? source : defaultDocumentSource,
      version: version is String ? version : lexicalCompatibleVersion,
    );
  }

  /// Parses a `.lexical` file's text.
  ///
  /// A file from somewhere else is untrusted input: anything that is not a
  /// JSON object with an editor state in it fails as a typed
  /// [MalformedDocumentException] rather than as whatever `jsonDecode` felt
  /// like throwing.
  factory SerializedDocument.parse(String text) {
    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException catch (error) {
      throw MalformedDocumentException('Not a JSON document: ${error.message}');
    }
    if (decoded is! Map<String, Object?>) {
      throw const MalformedDocumentException(
        'A .lexical document must be a JSON object.',
      );
    }
    return SerializedDocument.fromJson(decoded);
  }

  /// The envelope as JSON, in upstream's field order.
  Map<String, Object?> toJson() => <String, Object?>{
    'editorState': editorState,
    'lastSaved': lastSaved,
    'source': source,
    'version': version,
  };

  /// The envelope as the text of a `.lexical` file.
  String encode() => jsonEncode(toJson());

  /// A copy with individual fields replaced.
  SerializedDocument copyWith({
    Map<String, Object?>? editorState,
    int? lastSaved,
    String? source,
    String? version,
  }) => SerializedDocument(
    editorState: editorState ?? this.editorState,
    lastSaved: lastSaved ?? this.lastSaved,
    source: source ?? this.source,
    version: version ?? this.version,
  );

  @override
  bool operator ==(Object other) =>
      other is SerializedDocument &&
      other.lastSaved == lastSaved &&
      other.source == source &&
      other.version == version &&
      jsonDeepEquals(other.editorState, editorState);

  @override
  int get hashCode => Object.hash(lastSaved, source, version);

  @override
  String toString() =>
      'SerializedDocument(source: $source, version: $version, '
      'lastSaved: ${lastSavedAt.toIso8601String()})';
}

/// Wraps [state] in an envelope ready to be written to a file.
///
/// [lastSaved] defaults to now, as upstream's does. Pass it explicitly when
/// the result has to be reproducible — a test comparing two encodings, or a
/// document whose bytes should not change unless its content did.
SerializedDocument serializedDocumentFromEditorState(
  EditorState state, {
  String source = defaultDocumentSource,
  DateTime? lastSaved,
}) => SerializedDocument(
  editorState: state.toJson(),
  lastSaved: (lastSaved ?? DateTime.now()).toUtc().millisecondsSinceEpoch,
  source: source,
);

/// Parses the state inside [document] with [editor]'s node registry.
///
/// The editor is needed because node types are per-editor: the same `image`
/// type may be a different class in two applications, and only the registry
/// knows which. This does **not** install the state — call
/// [LexicalEditor.setEditorState] when the caller is ready for it, so a file
/// that fails to parse leaves the open document alone.
EditorState editorStateFromSerializedDocument(
  LexicalEditor editor,
  SerializedDocument document,
) => editor.parseEditorState(document.editorState);

/// The file name upstream's download button suggests: an ISO timestamp.
///
/// Sortable, unique enough for a downloads folder, and free of the characters
/// a file system objects to — a document title would satisfy none of the
/// three.
String suggestedDocumentFileName([DateTime? now]) =>
    '${(now ?? DateTime.now()).toUtc().toIso8601String()}.lexical';
