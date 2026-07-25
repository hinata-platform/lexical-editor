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

  @override
  ElementNode insertNewAfter({required bool isAtEnd}) {
    // Enter always leaves the quote, even from the middle of one — that is
    // what Lexical web does, and a document edited on both must behave the
    // same way on both. To continue a quote, press Shift-Enter, which is a
    // line break rather than a block split.
    final paragraph = $createParagraphNode();
    paragraph.setDirection(getDirection());
    insertAfter(paragraph);
    return paragraph;
  }
}

/// Creates a quote, applying any registered node replacement.
QuoteNode $createQuoteNode() => $applyNodeReplacement(QuoteNode());
