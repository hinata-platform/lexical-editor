/**
 * playground_nodes.mjs — the Lexical playground's node types, re-declared for
 * headless use.
 *
 * `layout-container`, `layout-item` and `image` are not published in any
 * `@lexical/*` package: they live in `lexical-playground`, which is a React
 * app. Their serialized shapes are still the ones Lexical web documents carry,
 * so the generator registers these copies to produce and check fixtures.
 *
 * Only the model half is reproduced — fields, clone, import/export and the
 * structural policy (shadow root, can-be-empty). DOM and React code is left
 * out because headless never calls it. Mirrors lexical v0.48.0:
 *   packages/lexical-playground/src/nodes/LayoutContainerNode.ts
 *   packages/lexical-playground/src/nodes/LayoutItemNode.ts
 *   packages/lexical-playground/src/nodes/ImageNode.tsx
 *
 * Copyright (c) Meta Platforms, Inc. and affiliates. MIT licensed; see the
 * repository NOTICE.
 */

export async function playgroundNodes() {
  const L = await import('lexical');

  class LayoutContainerNode extends L.ElementNode {
    constructor(templateColumns, key) {
      super(key);
      this.__templateColumns = templateColumns;
    }

    static getType() {
      return 'layout-container';
    }

    static clone(node) {
      return new LayoutContainerNode(node.__templateColumns, node.__key);
    }

    createDOM() {
      return null;
    }

    updateDOM() {
      return false;
    }

    static importJSON(json) {
      return $createLayoutContainerNode().updateFromJSON(json);
    }

    updateFromJSON(serializedNode) {
      return super
        .updateFromJSON(serializedNode)
        .setTemplateColumns(serializedNode.templateColumns);
    }

    isShadowRoot() {
      return true;
    }

    canBeEmpty() {
      return false;
    }

    exportJSON() {
      return {...super.exportJSON(), templateColumns: this.__templateColumns};
    }

    getTemplateColumns() {
      return this.getLatest().__templateColumns;
    }

    setTemplateColumns(templateColumns) {
      const self = this.getWritable();
      self.__templateColumns = templateColumns;
      return self;
    }
  }

  function $createLayoutContainerNode(templateColumns = '') {
    return new LayoutContainerNode(templateColumns);
  }

  class LayoutItemNode extends L.ElementNode {
    static getType() {
      return 'layout-item';
    }

    static clone(node) {
      return new LayoutItemNode(node.__key);
    }

    createDOM() {
      return null;
    }

    updateDOM() {
      return false;
    }

    static importJSON(serializedNode) {
      return $createLayoutItemNode().updateFromJSON(serializedNode);
    }

    isShadowRoot() {
      return true;
    }
  }

  function $createLayoutItemNode() {
    return new LayoutItemNode();
  }

  class ImageNode extends L.DecoratorNode {
    constructor(src, altText, maxWidth, width, height, showCaption, caption, key) {
      super(key);
      this.__src = src;
      this.__altText = altText;
      this.__maxWidth = maxWidth;
      this.__width = width || 'inherit';
      this.__height = height || 'inherit';
      this.__showCaption = showCaption || false;
      this.__caption = caption || L.createEditor({nodes: []});
    }

    static getType() {
      return 'image';
    }

    static clone(node) {
      return new ImageNode(
        node.__src,
        node.__altText,
        node.__maxWidth,
        node.__width,
        node.__height,
        node.__showCaption,
        node.__caption,
        node.__key,
      );
    }

    static importJSON(serializedNode) {
      const {altText, height, width, maxWidth, src, showCaption} = serializedNode;
      return $createImageNode({altText, height, maxWidth, showCaption, src, width})
        .updateFromJSON(serializedNode);
    }

    updateFromJSON(serializedNode) {
      const node = super.updateFromJSON(serializedNode);
      const {caption} = serializedNode;
      const nestedEditor = node.__caption;
      const editorState = nestedEditor.parseEditorState(caption.editorState);
      if (!editorState.isEmpty()) {
        nestedEditor.setEditorState(editorState);
      }
      return node;
    }

    exportJSON() {
      return {
        ...super.exportJSON(),
        altText: this.__altText,
        caption: this.__caption.toJSON(),
        height: this.__height === 'inherit' ? 0 : this.__height,
        maxWidth: this.__maxWidth,
        showCaption: this.__showCaption,
        src: this.__src,
        width: this.__width === 'inherit' ? 0 : this.__width,
      };
    }

    createDOM() {
      return null;
    }

    updateDOM() {
      return false;
    }

    decorate() {
      return null;
    }
  }

  function $createImageNode({altText, height, maxWidth = 500, src, width, showCaption, caption, key}) {
    return L.$applyNodeReplacement(
      new ImageNode(src, altText, maxWidth, width, height, showCaption, caption, key),
    );
  }

  return {
    nodes: [LayoutContainerNode, LayoutItemNode, ImageNode],
    $createLayoutContainerNode,
    $createLayoutItemNode,
    $createImageNode,
  };
}
