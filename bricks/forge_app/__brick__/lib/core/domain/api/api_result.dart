/// A typed wrapper for the outcome of an asynchronous data operation.
///
/// Either a [Success] carrying [Success.data] or a [Failure] carrying a
/// human-readable message and an optional HTTP [Failure.statusCode].
sealed class ApiResult<T> {
  const ApiResult();
}

class Success<T> extends ApiResult<T> {
  final T data;
  const Success(this.data);
}

class Failure<T> extends ApiResult<T> {
  final String message;
  final int? statusCode;
  const Failure(this.message, {this.statusCode});
}
