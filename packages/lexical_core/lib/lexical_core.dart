/// A Dart port of the Lexical editor's core state model.
///
/// This library is the engine: an immutable, double-buffered document state
/// built from a node map and sibling pointers, a per-editor node registry,
/// and JSON import/export that is wire-compatible with Lexical 0.48. It has
/// **no Flutter dependency** and runs under `dart test`.
///
/// Rendering, input and selection live in `lexical_flutter`; feature node
/// types live in their own packages. Keeping the model free of the widget
/// lifecycle is what makes it testable headlessly and what keeps the layering
/// honest.
///
/// ```dart
/// final editor = LexicalEditor();
/// editor.update(() {
///   final paragraph = $createParagraphNode()
///     ..append($createTextNode('Hallo Welt'));
///   $getRoot().append(paragraph);
/// }, discrete: true);
/// print(editor.toJsonString());
/// ```
library;

export 'src/commands.dart'
    show
        CommandHandler,
        CommandPriority,
        LexicalCommand,
        Unsubscribe,
        canRedoCommand,
        canUndoCommand,
        clearEditorCommand,
        clearHistoryCommand,
        deleteCharacterCommand,
        deleteLineCommand,
        deleteWordCommand,
        formatElementCommand,
        formatTextCommand,
        indentContentCommand,
        insertLineBreakCommand,
        insertParagraphCommand,
        insertTabCommand,
        insertTextCommand,
        outdentContentCommand,
        redoCommand,
        removeTextCommand,
        replaceTextCommand,
        selectAllCommand,
        selectionChangeCommand,
        undoCommand;
export 'src/editing.dart' show maxIndent, registerPlainText, registerRichText;
export 'src/editor.dart'
    show DirtyType, EditorConfig, LexicalEditor, UnknownNodePolicy, coreNodes;
export 'src/editor_state.dart' show EditorState;
export 'src/errors.dart'
    show
        ImportLimitExceededException,
        LexicalException,
        LexicalImportException,
        LexicalStateError,
        LexicalTreeError,
        MalformedDocumentException,
        UnknownNodeTypeException;
export 'src/integrity.dart' show assertTreeIntegrity;
export 'src/json/import_limits.dart' show ImportLimits;
export 'src/json/json_equality.dart' show jsonDeepEquals, jsonFirstDifference;
export 'src/keys.dart' show NodeKey;
export 'src/listeners.dart'
    show
        EditableListener,
        EditorUpdate,
        MutationListener,
        NodeMutation,
        TextContentListener,
        UpdateListener;
export 'src/node_state.dart' show NodeState, nodeStateKey;
export 'src/nodes/decorator_node.dart' show DecoratorNode;
export 'src/nodes/element_node.dart'
    show ElementFormat, ElementNode, NodeDirection;
export 'src/nodes/lexical_node.dart' show LexicalNode;
export 'src/nodes/line_break_node.dart'
    show LineBreakNode, $createLineBreakNode;
export 'src/nodes/paragraph_node.dart' show ParagraphNode, $createParagraphNode;
export 'src/nodes/root_node.dart' show RootNode;
export 'src/nodes/tab_node.dart' show TabNode, $createTabNode;
export 'src/nodes/text_node.dart'
    show TextDetail, TextFormat, TextMode, TextNode, $createTextNode;
export 'src/nodes/unknown_node.dart' show UnknownNode;
export 'src/registry.dart' show NodeRegistry, NodeReplacement, NodeSpec;
export 'src/selection.dart'
    show
        BaseSelection,
        NodeSelection,
        Point,
        PointType,
        RangeSelection,
        $getSelection,
        $setSelection;
export 'src/selection_ops.dart'
    show
        ElementNodeSelection,
        LexicalNodeSelection,
        RangeSelectionEditing,
        SelectionUnit,
        TextNodeSelection,
        $createRangeSelection,
        $getNearestBlock,
        $getNextBlock,
        $getPreviousBlock,
        $isBlock,
        $selectAll,
        $setBlocksType;
export 'src/transforms.dart' show NodeTransform, maxTransformCycles;
export 'src/updates.dart'
    show
        isCurrentlyReadOnlyMode,
        $applyNodeReplacement,
        $getActiveEditor,
        $getActiveEditorState,
        $getNodeByKey,
        $getRoot;
