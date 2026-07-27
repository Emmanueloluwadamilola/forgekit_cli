import 'package:flutter_test/flutter_test.dart';
// Imported with a prefix because `result.dart` declares `Error`, which would
// otherwise shadow `dart:core`'s `Error` for the whole file.
import 'package:{{name.snakeCase()}}/utils/result.dart' as res;

/// Starter test so a freshly generated project has a passing suite and a working
/// CI run from the first commit. Replace or extend it as the app grows.
void main() {
  group('Result', () {
    test('Ok carries its value', () {
      const outcome = res.Ok<int>(7);

      expect(outcome.value, 7);
      expect(outcome, isA<res.Result<int>>());
    });

    test('Error carries its error', () {
      const outcome = res.Error<int>('boom');

      expect(outcome.error, 'boom');
    });

    test('switch over the sealed type is exhaustive', () {
      String describe(res.Result<int> outcome) => switch (outcome) {
            res.Ok<int>(value: final value) => 'ok:$value',
            res.Error<int>(error: final error) => 'err:$error',
          };

      expect(describe(const res.Ok(1)), 'ok:1');
      expect(describe(const res.Error('boom')), 'err:boom');
    });
  });
}
