/// Resource bounds applied while decoding an untrusted document.
library;

import '../errors.dart';

/// Bounds enforced by the JSON importer.
///
/// A stored document is untrusted input: it may arrive from a collaborator,
/// a clipboard, or a server that was compromised. Without bounds, a document
/// nested a million levels deep is a denial of service, and a document with
/// a hundred million nodes exhausts memory before any application code sees
/// it.
///
/// The defaults are generous enough that no human-authored document reaches
/// them and tight enough that a hostile one fails fast. Pass
/// [ImportLimits.unbounded] to disable the checks for trusted input.
final class ImportLimits {
  /// Creates a set of import limits.
  const ImportLimits({
    this.maxDepth = 128,
    this.maxNodeCount = 250000,
    this.maxTextLength = 1 << 22,
    this.maxTotalTextLength = 1 << 26,
  });

  /// The default limits, suitable for untrusted input.
  static const ImportLimits defaults = ImportLimits();

  /// Limits that never trigger. Only for input you produced yourself.
  static const ImportLimits unbounded = ImportLimits(
    maxDepth: 1 << 30,
    maxNodeCount: 1 << 30,
    maxTextLength: 1 << 30,
    maxTotalTextLength: 1 << 30,
  );

  /// Maximum element nesting depth, counting the root as depth 1.
  final int maxDepth;

  /// Maximum number of nodes in one document.
  final int maxNodeCount;

  /// Maximum length in UTF-16 code units of a single text node.
  final int maxTextLength;

  /// Maximum combined length in UTF-16 code units of all text nodes.
  final int maxTotalTextLength;
}

/// Mutable counters that enforce an [ImportLimits] over one import run.
final class ImportBudget {
  /// Creates a budget for [limits].
  ImportBudget(this.limits);

  /// The limits being enforced.
  final ImportLimits limits;

  int _nodes = 0;
  int _text = 0;

  /// Records one decoded node, throwing when the node budget is exhausted.
  void countNode() {
    if (++_nodes > limits.maxNodeCount) {
      throw ImportLimitExceededException(
        'maxNodeCount',
        'document exceeds ${limits.maxNodeCount} nodes',
      );
    }
  }

  /// Validates the depth of the node currently being decoded.
  void checkDepth(int depth) {
    if (depth > limits.maxDepth) {
      throw ImportLimitExceededException(
        'maxDepth',
        'document nests deeper than ${limits.maxDepth} levels',
      );
    }
  }

  /// Records a decoded text run, throwing when a text budget is exhausted.
  void countText(int length) {
    if (length > limits.maxTextLength) {
      throw ImportLimitExceededException(
        'maxTextLength',
        'text node longer than ${limits.maxTextLength} code units',
      );
    }
    _text += length;
    if (_text > limits.maxTotalTextLength) {
      throw ImportLimitExceededException(
        'maxTotalTextLength',
        'document text longer than ${limits.maxTotalTextLength} code units',
      );
    }
  }
}
