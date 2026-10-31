import 'package:lexical_core/lexical_core.dart';
import 'package:test/test.dart';

void main() {
  group('parseCssColorValue', () {
    test('reads hex, functional and named colours as ARGB', () {
      expect(parseCssColorValue('#e60000'), 0xFFE60000);
      expect(parseCssColorValue('#FFF'), 0xFFFFFFFF);
      expect(parseCssColorValue('#00000080'), 0x80000000);
      expect(parseCssColorValue('rgb(230, 0, 0)'), 0xFFE60000);
      expect(parseCssColorValue('rgba(0,0,0,0.5)'), 0x80000000);
      expect(parseCssColorValue('rgb(100% 0% 0%)'), 0xFFFF0000);
      expect(parseCssColorValue('White'), 0xFFFFFFFF);
      expect(parseCssColorValue('rebeccapurple'), 0xFF663399);
      expect(parseCssColorValue('transparent'), 0x00000000);
    });

    test('anything else is not a colour, and never throws', () {
      for (final bad in [
        '',
        '#12',
        '#ggg',
        'hsl(0, 100%, 50%)',
        'currentColor',
        'rgb(1,2)',
        'rgb(a,b,c)',
        'x' * 1000,
        null,
      ]) {
        expect(parseCssColorValue(bad), isNull, reason: '$bad');
      }
    });
  });

  group('parseCssPixels', () {
    test('px, pt, em and bare numbers', () {
      expect(parseCssPixels('16px'), 16);
      expect(parseCssPixels('12pt'), 16);
      expect(parseCssPixels('1.5em'), 24);
      expect(parseCssPixels('0'), 0);
      expect(parseCssPixels(' 8PX '), 8);
    });

    test('percent, auto, negatives and junk answer null', () {
      for (final bad in ['50%', 'auto', '-4px', '4vw', 'px', '1e9px']) {
        expect(parseCssPixels(bad), isNull, reason: bad);
      }
    });

    test('is bounded', () {
      expect(parseCssPixels('99999999px'), maxCssLength);
    });
  });

  group('BlockCss.parse', () {
    test('reads the allowed subset', () {
      final css = BlockCss.parse(
        'background-color:#e60000;color:#fff;padding:16px 24px;'
        'border-radius:8px;margin-top:12px;margin-bottom:4pt;'
        'max-width:600px;width:50%;border:1px solid #cccccc',
      );
      expect(css.backgroundColor, 0xFFE60000);
      expect(css.color, 0xFFFFFFFF);
      expect(
        css.padding,
        const CssEdges(top: 16, right: 24, bottom: 16, left: 24),
      );
      expect(css.borderRadius, const CssCorners.all(8));
      expect(css.marginTop, 12);
      expect(css.marginBottom, closeTo(5.333, 0.001));
      expect(css.maxWidth, 600);
      expect(css.width, const CssLength(50, CssLengthUnit.percent));
      expect(css.borderTop, const CssBorderSide(1, 0xFFCCCCCC));
      expect(css.borderLeft, const CssBorderSide(1, 0xFFCCCCCC));
      expect(css.centered, isFalse);
    });

    test('auto horizontal margins centre the block', () {
      expect(BlockCss.parse('margin:0 auto').centered, isTrue);
      expect(BlockCss.parse('margin: 10px auto 20px').marginBottom, 20);
      expect(
        BlockCss.parse('margin-left:auto;margin-right:auto').centered,
        isTrue,
      );
      expect(BlockCss.parse('margin-left:auto').centered, isFalse);
      expect(BlockCss.parse('margin:0 auto;margin-left:0').centered, isFalse);
    });

    test('longhands refine the shorthand, in source order', () {
      final css = BlockCss.parse('padding:8px;padding-left:20px');
      expect(
        css.padding,
        const CssEdges(top: 8, right: 8, bottom: 8, left: 20),
      );
      final border = BlockCss.parse(
        'border:1px solid #000;border-bottom:2px dashed red;border-top:none',
      );
      expect(border.borderTop, isNull);
      expect(border.borderBottom, const CssBorderSide(2, 0xFFFF0000));
      expect(border.borderLeft, const CssBorderSide(1, 0xFF000000));
    });

    test('a border without a style draws nothing, as in CSS', () {
      expect(BlockCss.parse('border:1px #000').hasBorder, isFalse);
      expect(BlockCss.parse('border:0').hasBorder, isFalse);
      expect(BlockCss.parse('border:solid').borderTop?.width, 3);
    });

    test('unknown properties and bad values are ignored', () {
      final css = BlockCss.parse(
        'display:flex;position:fixed;background-color:nope;'
        'padding:1px 2px 3px 4px 5px;'
        'color:red !important;width:auto',
      );
      expect(css.backgroundColor, isNull);
      expect(css.padding.isEmpty, isTrue);
      expect(css.color, 0xFFFF0000);
      expect(css.width, isNull);
    });

    test('is bounded and never throws', () {
      expect(
        BlockCss.parse('color:red;${' ' * maxBlockStyleLength}'),
        BlockCss.empty,
      );
      for (final junk in [
        ';;;',
        ':',
        '((((',
        '"unterminated',
        '/* x',
        'a:b:c',
      ]) {
        expect(() => BlockCss.parse(junk), returnsNormally, reason: junk);
      }
    });
  });

  group('fit-content', () {
    test('shrinks the block to its content', () {
      final css = BlockCss.parse('width:fit-content;margin:0 auto');
      expect(css.fitContent, isTrue);
      expect(css.width, isNull);
      expect(css.centered, isTrue);
      expect(BlockCss.parse(css.toCss()), css);
      expect(css.toCss(), contains('width:fit-content'));
    });

    test('a later width replaces it, and auto clears it', () {
      expect(BlockCss.parse('width:fit-content;width:200px').fitContent, false);
      expect(BlockCss.parse('width:200px;width:fit-content').width, isNull);
      expect(BlockCss.parse('width:fit-content;width:auto').isEmpty, isTrue);
    });
  });

  group('border-radius', () {
    test('reads one to four values, in CSS corner order', () {
      expect(
        BlockCss.parse('border-radius:8px').borderRadius,
        const CssCorners.all(8),
      );
      expect(
        BlockCss.parse('border-radius:8px 0').borderRadius,
        const CssCorners(topLeft: 8, topRight: 0, bottomRight: 8, bottomLeft: 0),
      );
      expect(
        BlockCss.parse('border-radius:1px 2px 3px').borderRadius,
        const CssCorners(topLeft: 1, topRight: 2, bottomRight: 3, bottomLeft: 2),
      );
      expect(
        BlockCss.parse('border-radius:1px 2px 3px 4px').borderRadius,
        const CssCorners(topLeft: 1, topRight: 2, bottomRight: 3, bottomLeft: 4),
      );
      // The elliptical form keeps its horizontal radii.
      expect(
        BlockCss.parse('border-radius:4px / 8px').borderRadius,
        const CssCorners.all(4),
      );
    });

    test('a value that does not parse is no radius', () {
      expect(BlockCss.parse('border-radius:1px x').borderRadius, isNull);
      expect(
        BlockCss.parse('border-radius:1px 2px 3px 4px 5px').borderRadius,
        isNull,
      );
    });

    test('round-trips through toCss', () {
      for (final source in ['border-radius:4px', 'border-radius:0 8px 0 8px']) {
        final css = BlockCss.parse(source);
        expect(BlockCss.parse(css.toCss()), css, reason: source);
      }
      expect(BlockCss.parse('border-radius:4px').toCss(), 'border-radius:4px');
    });
  });

  group('--stack-below', () {
    test('reads a bounded pixel width', () {
      expect(BlockCss.parse('--stack-below:480px').stackBelow, 480);
      expect(BlockCss.parse('--stack-below: 30em').stackBelow, 480);
      // Past the bound it is dropped, not clamped — as the server does, so
      // both read the same document the same way.
      expect(BlockCss.parse('--stack-below:2000px').stackBelow, maxStackBelow);
      expect(BlockCss.parse('--stack-below:2001px').stackBelow, isNull);
      for (final bad in ['50%', 'auto', '-4px', 'big']) {
        expect(BlockCss.parse('--stack-below:$bad').stackBelow, isNull);
      }
    });

    test('round-trips through toCss', () {
      final css = BlockCss.parse('--stack-below:480px;padding:4px');
      expect(css.toCss(), contains('--stack-below:480px'));
      expect(BlockCss.parse(css.toCss()), css);
    });
  });

  group('BlockCss.toCss', () {
    test('writes the allowed subset in one spelling', () {
      final css = BlockCss.parse(
        'background:#E60000;padding:10px 25px;margin:0 auto;display:flex;'
        'border:1px solid red;border-radius:4px;width:50%;color:rgba(0,0,0,.5)',
      );
      expect(
        css.toCss(),
        'background-color:#e60000;color:rgba(0,0,0,0.5);'
        'padding:10px 25px 10px 25px;margin-top:0px;margin-bottom:0px;'
        'margin-left:auto;margin-right:auto;width:50%;border-radius:4px;'
        'border-top:1px solid #ff0000;border-right:1px solid #ff0000;'
        'border-bottom:1px solid #ff0000;border-left:1px solid #ff0000',
      );
    });

    test('reads back as the same style', () {
      for (final source in [
        'padding:8px;max-width:600px;margin:0 auto',
        'border-bottom:2px dashed #ccc;margin-bottom:12pt',
        'width:320px;background-color:transparent',
        '',
      ]) {
        final css = BlockCss.parse(source);
        expect(BlockCss.parse(css.toCss()), css, reason: source);
      }
    });
  });

  group('block style on a node', () {
    test('is stored as NodeState and round-trips under "\$"', () {
      final editor = LexicalEditor();
      editor.update(() {
        final paragraph = $createParagraphNode()
          ..append($createTextNode('Rot'));
        $setBlockStyle(paragraph, 'background-color:#e60000');
        $getRoot().append(paragraph);
      }, discrete: true);

      final json = editor.toJson();
      final paragraph =
          ((json['root']! as Map)['children']! as List).first as Map;
      expect(paragraph[r'$'], {'style': 'background-color:#e60000'});

      final reopened = LexicalEditor()
        ..setEditorState(editor.parseEditorState(json));
      expect(
        reopened.read(() => $getBlockStyle($getRoot().getFirstChild()!)),
        'background-color:#e60000',
      );
      expect(jsonFirstDifference(json, reopened.toJson()), isNull);
    });

    test('writing does not leak into the committed version', () {
      final editor = LexicalEditor();
      editor.update(() {
        final paragraph = $createParagraphNode();
        $setBlockStyle(paragraph, 'color:red');
        $getRoot().append(paragraph);
      }, discrete: true);
      final before = editor.editorState;

      editor.update(() {
        $setBlockStyle($getRoot().getFirstChild()!, 'color:blue');
      }, discrete: true);

      expect(
        before.read(() => $getBlockStyle($getRoot().getFirstChild()!)),
        'color:red',
      );
      expect(
        editor.read(() => $getBlockStyle($getRoot().getFirstChild()!)),
        'color:blue',
      );
    });

    test('an empty style removes the entry and keeps other state', () {
      final editor = LexicalEditor();
      editor.update(() {
        final paragraph = $createParagraphNode();
        paragraph.nodeState['other'] = 1;
        $setBlockStyle(paragraph, 'color:red');
        $setBlockStyle(paragraph, '');
        $getRoot().append(paragraph);
      }, discrete: true);
      final paragraph =
          ((editor.toJson()['root']! as Map)['children']! as List).first as Map;
      expect(paragraph[r'$'], {'other': 1});
    });

    test('a node without one answers the empty string', () {
      final editor = LexicalEditor();
      editor.update(() {
        $getRoot().append($createParagraphNode());
      }, discrete: true);
      expect(
        editor.read(() => $getBlockStyle($getRoot().getFirstChild()!)),
        '',
      );
    });
  });
}
