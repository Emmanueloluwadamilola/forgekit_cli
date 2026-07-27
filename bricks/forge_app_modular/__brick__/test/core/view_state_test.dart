import 'package:flutter_test/flutter_test.dart';
import 'package:{{name.snakeCase()}}/core/state/view_state.dart';

/// Starter test so a freshly generated project has a passing suite and a working
/// CI run from the first commit. Replace or extend it as the app grows.
void main() {
  group('ViewState', () {
    test('defaults to idle with no error message', () {
      const state = ViewState();

      expect(state.status, ViewStatus.idle);
      expect(state.errorMessage, isNull);
      expect(state.isLoading, isFalse);
      expect(state.hasError, isFalse);
    });

    test('reports loading', () {
      const state = ViewState(status: ViewStatus.loading);

      expect(state.isLoading, isTrue);
      expect(state.hasError, isFalse);
    });

    test('reports an error with its message', () {
      const state = ViewState(
        status: ViewStatus.error,
        errorMessage: 'boom',
      );

      expect(state.hasError, isTrue);
      expect(state.isLoading, isFalse);
      expect(state.errorMessage, 'boom');
    });
  });
}
