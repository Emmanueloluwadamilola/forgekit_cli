import 'package:flutter_test/flutter_test.dart';
import 'package:{{name.snakeCase()}}/core/domain/api/api_result.dart';

/// Starter test so a freshly generated project has a passing suite and a working
/// CI run from the first commit. Replace or extend it as the app grows.
void main() {
  group('ApiResult', () {
    test('Success carries its data', () {
      const result = Success<int>(7);

      expect(result.data, 7);
      expect(result, isA<ApiResult<int>>());
    });

    test('Failure carries a message and an optional status code', () {
      const result = Failure<int>('Not found', statusCode: 404);

      expect(result.message, 'Not found');
      expect(result.statusCode, 404);
    });

    test('Failure defaults its status code to null', () {
      const result = Failure<int>('Offline');

      expect(result.statusCode, isNull);
    });

    test('switch over the sealed type is exhaustive', () {
      String describe(ApiResult<int> result) => switch (result) {
            Success<int>(data: final data) => 'ok:$data',
            Failure<int>(message: final message) => 'err:$message',
          };

      expect(describe(const Success(1)), 'ok:1');
      expect(describe(const Failure('boom')), 'err:boom');
    });
  });
}
