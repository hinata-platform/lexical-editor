/// Block quotes.
library;

import 'package:lexical_core/lexical_core.dart';

/// A block quote.
///
/// It carries no fields of its own — only the element base shape — so the
/// whole implementation is its type string and its clone.
class QuoteNode extends ElementNode {
  /// Creates an empty quote.
  QuoteNode();

  @override
  String get type => 'quote';

  @override
  QuoteNode clone() => QuoteNode();
}

/// Creates a quote, applying any registered node replacement.
QuoteNode $createQuoteNode() => $applyNodeReplacement(QuoteNode());
