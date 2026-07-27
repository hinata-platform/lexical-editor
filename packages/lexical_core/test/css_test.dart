import 'package:lexical_core/lexical_core.dart';
import 'package:test/test.dart';

void main() {
  group('getStyleObjectFromCss', () {
    test('reads declarations, trimmed and in source order', () {
      expect(getStyleObjectFromCss('color: #f00; font-size: 12px'), {
        'color': '#f00',
        'font-size': '12px',
      });
      expect(getStyleObjectFromCss('color:#f00;font-size:12px;'), {
        'color': '#f00',
        'font-size': '12px',
      });
    });

    test('an empty string has no declarations', () {
      expect(getStyleObjectFromCss(''), isEmpty);
      expect(getStyleObjectFromCss('   '), isEmpty);
      expect(getStyleObjectFromCss(';;;'), isEmpty);
    });

    test('a declaration without a value is not one', () {
      // `color:` and a bare `font-weight` are both incomplete, and storing
      // either would write CSS back out that no parser reads.
      expect(getStyleObjectFromCss('color: ; font-weight'), isEmpty);
      expect(getStyleObjectFromCss('color: red; font-weight'), {
        'color': 'red',
      });
    });

    test('a semicolon inside parentheses is content, not a separator', () {
      // The failure this rules out: `background` truncated at the `;` inside
      // the url, and a stray `b)` declaration invented after it.
      expect(getStyleObjectFromCss('background: url(a;b); color: red'), {
        'background': 'url(a;b)',
        'color': 'red',
      });
    });

    test('a colon inside a value stays in the value', () {
      expect(getStyleObjectFromCss('background: url(http://x/y.png)'), {
        'background': 'url(http://x/y.png)',
      });
    });

    test('quotes are preserved, and separators inside them are literal', () {
      expect(getStyleObjectFromCss('font-family: "a;b", monospace'), {
        'font-family': '"a;b", monospace',
      });
      expect(getStyleObjectFromCss(r"content: 'it\'s'"), {
        'content': r"'it\'s'",
      });
    });

    test('comments are dropped without splitting what surrounds them', () {
      expect(getStyleObjectFromCss('col/* hm */or: red'), {'color': 'red'});
      expect(getStyleObjectFromCss('/* all of it */'), isEmpty);
    });

    test('the last property wins, as a browser would resolve it', () {
      expect(getStyleObjectFromCss('color: red; color: blue'), {
        'color': 'blue',
      });
    });

    test('an unknown property is carried through untouched', () {
      // The model does not decide what a renderer understands.
      expect(getStyleObjectFromCss('--brand-hue: 42deg'), {
        '--brand-hue': '42deg',
      });
    });
  });

  group('getCssFromStyleObject', () {
    test('writes each declaration in map order', () {
      expect(
        getCssFromStyleObject({'color': '#f00', 'font-size': '12px'}),
        'color: #f00;font-size: 12px;',
      );
    });

    test('an entry without a name is skipped', () {
      expect(
        getCssFromStyleObject({'': 'red', 'color': 'blue'}),
        'color: blue;',
      );
    });

    test('a parsed string survives a round trip through both', () {
      const css = 'color: #f00;font-family: "a;b", monospace;';
      expect(getCssFromStyleObject(getStyleObjectFromCss(css)), css);
    });
  });
}
