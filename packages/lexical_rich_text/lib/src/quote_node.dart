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
  bool collapseAtStart() {
    // Backspace at the start of a quote un-quotes it. Without this a quote at
    // the top of a document cannot be undone with the keyboard at all: there
    // is nothing before it to delete, so the key does nothing.
    final paragraph = $createParagraphNode();
    $copyBlockFormatIndent(this, paragraph);
    replace(paragraph, includeChildren: true);
    paragraph.selectStart();
    return true;
  }

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
