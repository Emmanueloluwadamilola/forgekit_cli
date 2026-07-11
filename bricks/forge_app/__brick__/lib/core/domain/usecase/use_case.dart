import '../api/api_result.dart';

/// Base contract for a single application use case.
///
/// [Type] is the success payload type, [Params] the input type
/// (use [NoParams] when no input is required).
abstract class UseCase<Type, Params> {
  Future<ApiResult<Type>> call(Params params);
}

class NoParams {
  const NoParams();
}
