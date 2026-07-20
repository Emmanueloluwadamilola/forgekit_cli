import '../api/api_result.dart';

/// Base contract for a single application use case.
///
/// [Output] is the success payload type, [Params] the input type
/// (use [NoParams] when no input is required).
abstract class UseCase<Output, Params> {
  Future<ApiResult<Output>> call(Params params);
}

class NoParams {
  const NoParams();
}
