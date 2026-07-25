import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
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

    test('unknown values are ignored rather than guessed', () {
      // Named colours are deliberately not resolved: a partial list is worse
      // than none, and the original string stays in the model regardless.
      expect(parseCssColor('rebeccapurple'), isNull);
      expect(parseCssColor('not a color'), isNull);
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
      'letter-spacing: 3px',
      base,
    );
    expect(resolved.color, const Color(0xFFFF0000));
    expect(resolved.fontSize, 20);
    expect(resolved.fontFamily, 'Inter');
    expect(resolved.fontFamilyFallback, ['sans-serif']);
    // letter-spacing is not in the supported subset and is ignored — the raw
    // string is still preserved in the model, so nothing is lost.
    expect(resolved.letterSpacing, isNull);
  });
}
