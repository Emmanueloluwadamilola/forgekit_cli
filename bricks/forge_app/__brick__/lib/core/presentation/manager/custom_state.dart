{{#useProvider}}
/// Lifecycle status for a view-state object.
enum ViewStatus { idle, loading, success, error }

/// Base immutable view-state. Feature `*State` classes extend this and add a
/// `copyWith` plus their own fields.
class CustomState {
  final ViewStatus status;
  final String? errorMessage;

  const CustomState({
    this.status = ViewStatus.idle,
    this.errorMessage,
  });

  bool get isLoading => status == ViewStatus.loading;
  bool get hasError => status == ViewStatus.error;
}
{{/useProvider}}
