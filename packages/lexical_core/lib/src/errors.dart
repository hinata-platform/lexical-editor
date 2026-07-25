/// Error types raised by the editor core.
///
/// Every failure mode is a distinct type so consumers can react to an
/// untrusted-document failure (`LexicalImportException` and its subtypes)
/// differently from a programming error (`LexicalStateError`).
library;

/// Base class for all errors raised by `lexical_core`.
sealed class LexicalException implements Exception {
  /// Creates an exception carrying a human-readable [message].
  const LexicalException(this.message);

  /// Human-readable description. Not intended for end users.
  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// Thrown when an API is used outside the editor context it requires.
///
/// Examples: mutating a node outside `LexicalEditor.update`, reading the
/// active state with no active state, or opening a nested update.
final class LexicalStateError extends LexicalException {
  /// Creates a state error.
  const LexicalStateError(super.message);
}

/// Thrown when the node tree violates a structural invariant.
///
/// Raised by the debug-only integrity walk and by mutators that would
/// create a cycle or orphan a node.
final class LexicalTreeError extends LexicalException {
  /// Creates a tree-integrity error.
  const LexicalTreeError(super.message);
}

/// Base class for failures while importing a serialized document.
///
/// A stored document is untrusted input, so every import failure is
/// catchable and carries enough context to be logged and rejected.
sealed class LexicalImportException extends LexicalException {
  /// Creates an import failure.
  const LexicalImportException(super.message);
}

/// Thrown when a serialized node names a type that is not registered.
///
/// This mirrors upstream Lexical, which throws on unknown types. Set
/// `EditorConfig.unknownNodePolicy` to `UnknownNodePolicy.preserve` to opt
/// into lossless preservation instead — see `UnknownNode`.
final class UnknownNodeTypeException extends LexicalImportException {
  /// Creates the exception for the unregistered [type].
  UnknownNodeTypeException(this.type)
    : super('parseEditorState: type "$type" not found');

  /// The unregistered `type` string read from the document.
  final String type;
}

/// Thrown when a serialized document is structurally malformed.
final class MalformedDocumentException extends LexicalImportException {
  /// Creates the exception with a description of what was malformed.
  const MalformedDocumentException(super.message);
}

/// Thrown when an import exceeds a configured resource limit.
///
/// Bounding the parser is what keeps a hostile document from turning into
/// a denial of service; see `ImportLimits`.
final class ImportLimitExceededException extends LexicalImportException {
  /// Creates the exception naming the [limit] that was exceeded.
  const ImportLimitExceededException(this.limit, super.message);

  /// Short identifier of the exceeded limit, e.g. `maxDepth`.
  final String limit;
}
