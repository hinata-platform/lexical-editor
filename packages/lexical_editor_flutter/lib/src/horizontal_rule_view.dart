/// How a thematic break is drawn.
library;

import 'package:flutter/widgets.dart';
import 'package:lexical_flutter/lexical_flutter.dart';

/// A thematic break: a hairline across the writing column.
///
/// Its colour comes from the surrounding text style rather than a theme of its
/// own, so a rule in a dark document is light and one in a light document is
/// dark without anybody configuring it. The opacity is what turns the text
/// colour into a rule instead of a stripe.
class LexicalHorizontalRuleView extends StatelessWidget {
  /// Creates a rule.
  const LexicalHorizontalRuleView({
    super.key,
    this.color,
    this.thickness = 1,
    this.spacing = 8,
  });

  /// Overrides the colour derived from the surrounding text.
  final Color? color;

  /// How thick the line is, in logical pixels.
  final double thickness;

  /// Space above and below it.
  final double spacing;

  @override
  Widget build(BuildContext context) {
    final inherited = DefaultTextStyle.of(context).style.color;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: spacing),
      child: SizedBox(
        height: thickness,
        width: double.infinity,
        child: ColoredBox(
          color:
              color ??
              (inherited ?? const Color(0xFF000000)).withValues(alpha: 0.16),
        ),
      ),
    );
  }
}

/// The builder for the `horizontalrule` decorator.
///
/// {@macro lexical_flutter.builder_read_scope}
Map<String, DecoratorBuilder> horizontalRuleDecoratorBuilders({
  Color? color,
  double thickness = 1,
  double spacing = 8,
}) => <String, DecoratorBuilder>{
  // The node carries no fields, so nothing is read off it here — which is also
  // why this builder cannot leak a node into a widget that outlives the read.
  'horizontalrule': (context, node) => LexicalHorizontalRuleView(
    color: color,
    thickness: thickness,
    spacing: spacing,
  ),
};
