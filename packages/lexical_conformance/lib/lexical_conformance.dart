/// Registers every node type this repository implements.
///
/// Test-only. Consumers pick the feature packages they actually need — that
/// is the point of the split — and a package that is omitted must not break
/// anything else. This library exists so the conformance suite can assert
/// the *whole* fixture corpus in one place.
library;

import 'package:lexical_code/lexical_code.dart';
import 'package:lexical_core/lexical_core.dart';
import 'package:lexical_hashtag/lexical_hashtag.dart';
import 'package:lexical_link/lexical_link.dart';
import 'package:lexical_list/lexical_list.dart';
import 'package:lexical_mark/lexical_mark.dart';
import 'package:lexical_rich_text/lexical_rich_text.dart';
import 'package:lexical_table/lexical_table.dart';

/// Every node spec contributed by the feature packages.
List<NodeSpec<LexicalNode>> get allFeatureNodes => <NodeSpec<LexicalNode>>[
  ...richTextNodes,
  ...listNodes,
  ...linkNodes,
  ...codeNodes,
  ...tableNodes,
  ...markNodes,
  ...hashtagNodes,
];

/// Creates an editor that understands every implemented node type.
LexicalEditor createFullEditor({EditorConfig? config}) => LexicalEditor(
  nodes: allFeatureNodes,
  config: config ?? const EditorConfig(),
);
