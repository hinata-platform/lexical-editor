/// Locating the render object of a block that is currently on screen.
library;

import 'package:flutter/widgets.dart';
import 'package:lexical_core/lexical_core.dart';

import '../render/block_offset_map.dart';
import '../render/render_lexical_block.dart';

/// What the input and selection layers need to know about a mounted block.
class MountedBlock {
  /// Records a mounted block.
  MountedBlock({
    required this.key,
    required this.offsets,
    required this.render,
  });

  /// The block's node key.
  final NodeKey key;

  /// The offset map built alongside the block's span.
  final BlockOffsetMap offsets;

  /// The block's render object, valid while it is mounted.
  final RenderLexicalBlock render;
}

/// The blocks currently mounted, keyed by node.
///
/// Only mounted blocks are registered, so a viewport-culled document keeps a
/// map proportional to what is on screen rather than to the document — which
/// is the whole point of culling.
class BlockRegistry {
  final Map<NodeKey, MountedBlock> _blocks = <NodeKey, MountedBlock>{};

  /// The mounted blocks, in no particular order.
  Iterable<MountedBlock> get blocks => _blocks.values;

  /// The mounted block for [key], or `null` when it is off screen.
  MountedBlock? operator [](NodeKey key) => _blocks[key];

  /// Registers a mounted block.
  void register(MountedBlock block) => _blocks[block.key] = block;

  /// Removes a block that has been unmounted.
  void unregister(NodeKey key) => _blocks.remove(key);

  /// The mounted block containing [nodeKey], or `null`.
  MountedBlock? blockContaining(NodeKey nodeKey) {
    final direct = _blocks[nodeKey];
    if (direct != null) return direct;
    for (final block in _blocks.values) {
      if (block.offsets.contains(nodeKey)) return block;
    }
    return null;
  }

  /// The mounted block under [globalPosition], or `null`.
  MountedBlock? blockAt(Offset globalPosition) {
    for (final block in _blocks.values) {
      final render = block.render;
      if (!render.attached || !render.hasSize) continue;
      final local = render.globalToLocal(globalPosition);
      if ((Offset.zero & render.size).contains(local)) return block;
    }
    return null;
  }

  /// Forgets every block. Called when the document is replaced.
  void clear() => _blocks.clear();
}

/// Makes the [BlockRegistry] of the enclosing document available to
/// descendants.
class BlockRegistryScope extends InheritedWidget {
  /// Provides [registry] to [child].
  const BlockRegistryScope({
    required this.registry,
    required super.child,
    super.key,
  });

  /// The registry of the enclosing document.
  final BlockRegistry registry;

  /// The registry of the nearest enclosing document, or `null`.
  static BlockRegistry? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<BlockRegistryScope>()
      ?.registry;

  @override
  bool updateShouldNotify(BlockRegistryScope oldWidget) =>
      oldWidget.registry != registry;
}

/// Registers its inline block with the enclosing [BlockRegistry] while
/// mounted.
class RegisteredBlock extends StatefulWidget {
  /// Registers the block identified by [nodeKey] with [offsets].
  const RegisteredBlock({
    required this.nodeKey,
    required this.offsets,
    required this.child,
    super.key,
  });

  /// The block's node key.
  final NodeKey nodeKey;

  /// The offset map for the block's inline content.
  final BlockOffsetMap offsets;

  /// The inline block widget.
  final Widget child;

  @override
  State<RegisteredBlock> createState() => _RegisteredBlockState();
}

class _RegisteredBlockState extends State<RegisteredBlock> {
  BlockRegistry? _registry;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _registry = BlockRegistryScope.maybeOf(context);
    // The render object only exists after the first layout pass, so
    // registration is deferred to the end of the frame.
    WidgetsBinding.instance.addPostFrameCallback((_) => _register());
  }

  @override
  void didUpdateWidget(RegisteredBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.nodeKey != widget.nodeKey) {
      _registry?.unregister(oldWidget.nodeKey);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _register());
  }

  void _register() {
    if (!mounted) return;
    final render = context.findRenderObject();
    if (render is! RenderLexicalBlock) return;
    _registry?.register(
      MountedBlock(
        key: widget.nodeKey,
        offsets: widget.offsets,
        render: render,
      ),
    );
  }

  @override
  void dispose() {
    _registry?.unregister(widget.nodeKey);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
