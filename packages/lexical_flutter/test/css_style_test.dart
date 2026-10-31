import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexical_core/lexical_core.dart';
import 'package:lexical_flutter/lexical_flutter.dart';

void main() {
  group('declarations', () {
    test('are split, trimmed and lower-cased', () {
      expect(parseCssDeclarations('color: #fff; FONT-SIZE : 14px ;'), {
        'color': '#fff',
        'font-size': '14px',
      });
    });

    test('malformed fragments are skipped, not thrown on', () {
      expect(parseCssDeclarations('color; :red; ;'), isEmpty);
      expect(parseCssDeclarations(''), isEmpty);
    });

    test('a separator inside a value is content, not a separator', () {
      // Splitting on `;` truncates the url and invents a `b)` declaration
      // after it; splitting on `,` breaks a quoted font stack the same way.
      expect(parseCssDeclarations('background: url(a;b); color: red'), {
        'background': 'url(a;b)',
        'color': 'red',
      });
      expect(parseCssDeclarations('font-family: "a;b", monospace'), {
        'font-family': '"a;b", monospace',
      });
    });
  });

  group('colors', () {
    test('hex forms', () {
      expect(parseCssColor('#f00'), const Color(0xFFFF0000));
      expect(parseCssColor('#ff0000'), const Color(0xFFFF0000));
      expect(parseCssColor('#ff000080'), const Color(0x80FF0000));
    });

    test('functional forms', () {
      expect(parseCssColor('rgb(255, 0, 0)'), const Color(0xFFFF0000));
      expect(parseCssColor('rgba(255, 0, 0, 0.5)')!.a, closeTo(0.5, 0.01));
    });

    test('named colours and transparent', () {
      expect(parseCssColor('rebeccapurple'), const Color(0xFF663399));
      expect(parseCssColor('White'), const Color(0xFFFFFFFF));
      expect(parseCssColor('transparent'), const Color(0x00000000));
    });

    test('unknown values are ignored rather than guessed', () {
      expect(parseCssColor('not a color'), isNull);
      expect(parseCssColor('hsl(0, 100%, 50%)'), isNull);
      expect(parseCssColor(null), isNull);
    });
  });

  group('lengths', () {
    test('absolute units', () {
      expect(parseCssLength('16px', 14), 16);
      expect(parseCssLength('12pt', 14), closeTo(16, 0.01));
    });

    test('relative units resolve against the inherited size', () {
      expect(parseCssLength('2em', 10), 20);
      expect(parseCssLength('150%', 10), 15);
    });

    test('unknown units are ignored', () {
      expect(parseCssLength('3vw', 14), isNull);
    });
  });

  test('font weights snap to a supported value', () {
    expect(parseCssFontWeight('bold'), FontWeight.w700);
    expect(parseCssFontWeight('600'), FontWeight.w600);
    expect(parseCssFontWeight('350'), FontWeight.w400);
    expect(parseCssFontWeight('schwer'), isNull);
  });

  test('text decorations combine', () {
    expect(parseCssTextDecoration('underline'), TextDecoration.underline);
    expect(parseCssTextDecoration('none'), TextDecoration.none);
    expect(
      parseCssTextDecoration('underline line-through'),
      TextDecoration.combine([
        TextDecoration.underline,
        TextDecoration.lineThrough,
      ]),
    );
  });

  test('the default resolver applies what it understands', () {
    const base = TextStyle(fontSize: 14);
    final resolved = defaultCssStyleResolver(
      'color: #ff0000; font-size: 20px; font-family: Inter, sans-serif; '
      'letter-spacing: 3px; display: flex',
      base,
    );
    expect(resolved.color, const Color(0xFFFF0000));
    expect(resolved.fontSize, 20);
    expect(resolved.fontFamily, 'Inter');
    // The generic family ends the stack: after it comes the platform's own
    // sans-serif, which is what the generic means.
    expect(resolved.fontFamilyFallback, isEmpty);
    expect(resolved.letterSpacing, 3);
  });

  group('mail text', () {
    const base = TextStyle(fontSize: 16);

    test('line-height as a number, a length or a percentage', () {
      expect(defaultCssStyleResolver('line-height: 1.5', base).height, 1.5);
      expect(
        defaultCssStyleResolver('font-size:14px;line-height:21px', base).height,
        closeTo(1.5, 0.001),
      );
      expect(defaultCssStyleResolver('line-height: 150%', base).height, 1.5);
      expect(defaultCssStyleResolver('line-height: normal', base).height, null);
    });

    test('font-size in px, pt and em', () {
      expect(defaultCssStyleResolver('font-size:12pt', base).fontSize, 16);
      expect(defaultCssStyleResolver('font-size:1.5em', base).fontSize, 24);
    });

    test('font-style and weight', () {
      final style = defaultCssStyleResolver(
        'font-style: italic; font-weight: 700',
        base,
      );
      expect(style.fontStyle, FontStyle.italic);
      expect(style.fontWeight, FontWeight.w700);
    });

    test('letter-spacing in em follows the font size', () {
      expect(
        defaultCssStyleResolver(
          'font-size:20px;letter-spacing:0.1em',
          base,
        ).letterSpacing,
        closeTo(2, 0.001),
      );
    });

    test('generic families map to faces the platforms have', () {
      expect(resolveCssFontFamily('Georgia, serif'), [
        'Georgia',
        'Times New Roman',
        'Noto Serif',
      ]);
      expect(
        resolveCssFontFamily("'Courier New', monospace").last,
        'Roboto Mono',
      );
      expect(resolveCssFontFamily('Arial, Helvetica, sans-serif'), [
        'Arial',
        'Helvetica',
      ]);
      expect(resolveCssFontFamily('sans-serif'), isEmpty);
      expect(
        defaultCssStyleResolver('font-family: sans-serif', base).fontFamily,
        isNull,
      );
    });

    test('text-transform is a case format bit', () {
      expect(
        cssTextTransformFormat('text-transform: uppercase'),
        TextFormat.uppercase.bit,
      );
      expect(cssTextTransformFormat('color: red'), 0);
      expect(cssTextTransformFormat('text-transform: none'), 0);
    });

    test('a style past the bound is ignored, not thrown on', () {
      final long = 'color: red;${' ' * maxTextStyleLength}';
      expect(defaultCssStyleResolver(long, base), base);
      expect(cssTextTransformFormat('text-transform:uppercase;$long'), 0);
    });
  });

  group('block style', () {
    test('a decoration with fill, border and radius', () {
      final decoration = blockCssDecoration(
        BlockCss.parse(
          'background-color:#e60000;border:1px solid #ccc;border-radius:8px',
        ),
      )!;
      expect(decoration.color, const Color(0xFFE60000));
      expect(decoration.borderRadius, BorderRadius.circular(8));
      expect((decoration.border! as Border).top.width, 1);
    });

    test('no radius on a border whose sides differ', () {
      final decoration = blockCssDecoration(
        BlockCss.parse('border-top:2px solid red;border-radius:8px'),
      )!;
      expect(decoration.borderRadius, isNull);
    });

    test('nothing to draw is no decoration', () {
      expect(blockCssDecoration(BlockCss.parse('padding:4px')), isNull);
    });

    test('padding makes room for the border', () {
      expect(
        blockCssPadding(BlockCss.parse('padding:10px 25px;border:2px solid')),
        const EdgeInsets.fromLTRB(27, 12, 27, 12),
      );
    });
  });
}
