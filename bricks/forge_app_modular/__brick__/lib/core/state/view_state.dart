enum ViewStatus { idle, loading, success, error }

class ViewState {
  const ViewState({
    this.status = ViewStatus.idle,
    this.errorMessage,
  });

  final ViewStatus status;
  final String? errorMessage;

  bool get isLoading => status == ViewStatus.loading;
  bool get hasError => status == ViewStatus.error;
}
