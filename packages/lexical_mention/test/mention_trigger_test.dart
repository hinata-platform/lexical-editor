import 'package:lexical_mention/lexical_mention.dart';
import 'package:test/test.dart';

const user = MentionTrigger(character: '@', mentionType: 'user');
const issue = MentionTrigger(character: '#', mentionType: 'issue');

void main() {
  group('matching', () {
    test('finds a trigger at the start of the text', () {
      final match = matchMentionTrigger('@reb', 4, [user]);
      expect(match, isNotNull);
      expect(match!.query, 'reb');
      expect(match.trigger.mentionType, 'user');
      expect(match.triggerOffset, 0);
      expect(match.caretOffset, 4);
    });

    test('finds a trigger after a space', () {
      final match = matchMentionTrigger('hallo @reb', 10, [user]);
      expect(match!.query, 'reb');
      expect(match.triggerOffset, 6);
    });

    test('opens on the bare trigger', () {
      final match = matchMentionTrigger('hallo @', 7, [user]);
      expect(match, isNotNull);
      expect(match!.query, '');
    });

    test('picks the right trigger when several are registered', () {
      expect(
        matchMentionTrigger('siehe #IT-3', 11, [user, issue])!.trigger,
        issue,
      );
      expect(matchMentionTrigger('cc @reb', 7, [user, issue])!.trigger, user);
    });
  });

  group('rejection', () {
    test('an email address does not open a people picker', () {
      // The whole reason requireLeadingBoundary defaults to true.
      expect(matchMentionTrigger('name@example.org', 16, [user]), isNull);
    });

    test('a space ends the query', () {
      expect(matchMentionTrigger('@reb ahmad', 10, [user]), isNull);
    });

    test('a newline ends the query', () {
      expect(matchMentionTrigger('@reb\nzweite', 11, [user]), isNull);
    });

    test('a caret before the trigger finds nothing', () {
      expect(matchMentionTrigger('hallo @reb', 3, [user]), isNull);
    });

    test('an empty text or no triggers finds nothing', () {
      expect(matchMentionTrigger('', 0, [user]), isNull);
      expect(matchMentionTrigger('@reb', 4, const []), isNull);
    });

    test('a query longer than the limit is abandoned', () {
      const short = MentionTrigger(
        character: '@',
        mentionType: 'user',
        maxQueryLength: 4,
      );
      expect(matchMentionTrigger('@abcd', 5, [short]), isNotNull);
      expect(matchMentionTrigger('@abcde', 6, [short]), isNull);
    });

    test('a minimum query length delays opening', () {
      const later = MentionTrigger(
        character: '/',
        mentionType: 'command',
        minQueryLength: 2,
      );
      expect(matchMentionTrigger('/a', 2, [later]), isNull);
      expect(matchMentionTrigger('/ab', 3, [later])!.query, 'ab');
    });
  });

  group('options', () {
    test('spaces can be allowed for name-style queries', () {
      const spaced = MentionTrigger(
        character: '@',
        mentionType: 'user',
        allowSpaces: true,
      );
      final match = matchMentionTrigger('cc @Rebar Ah', 12, [spaced]);
      expect(match!.query, 'Rebar Ah');
    });

    test('the leading boundary can be waived', () {
      const anywhere = MentionTrigger(
        character: '@',
        mentionType: 'user',
        requireLeadingBoundary: false,
      );
      expect(matchMentionTrigger('name@example', 12, [anywhere]), isNotNull);
    });
  });

  group('cost', () {
    test('scanning is bounded by the query limit, not the text length', () {
      // A pathological paragraph: the trigger is far behind the caret, and
      // matching must not walk the whole thing on every keystroke.
      final long = '${'x' * 200000} und weiter';
      final stopwatch = Stopwatch()..start();
      for (var i = 0; i < 2000; i++) {
        matchMentionTrigger(long, long.length, [user]);
      }
      stopwatch.stop();
      expect(
        stopwatch.elapsedMilliseconds,
        lessThan(500),
        reason: '2000 keystrokes over a 200k paragraph must stay cheap',
      );
    });

    test('the replaced range covers the trigger', () {
      final match = matchMentionTrigger('cc @reb', 7, [user])!;
      expect(match.replaceStart, 3);
      expect(match.replaceEnd, 7);
    });
  });
}
