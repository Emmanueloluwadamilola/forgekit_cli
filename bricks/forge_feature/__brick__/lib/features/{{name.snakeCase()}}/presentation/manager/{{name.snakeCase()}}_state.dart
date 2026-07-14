{{#useProvider}}import 'package:{{projectName}}/core/presentation/manager/custom_state.dart';

/// View-state for the {{name.pascalCase()}} screen.
class {{name.pascalCase()}}State extends CustomState {
  const {{name.pascalCase()}}State({
    super.status,
    super.errorMessage,
  });

  {{name.pascalCase()}}State copyWith({
    ViewStatus? status,
    String? errorMessage,
  }) {
    return {{name.pascalCase()}}State(
      status: status ?? this.status,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}
{{/useProvider}}{{^useProvider}}enum {{name.pascalCase()}}Status { idle, loading, success, error }

/// Immutable state for the {{name.pascalCase()}} feature.
class {{name.pascalCase()}}State {
  const {{name.pascalCase()}}State({
    this.status = {{name.pascalCase()}}Status.idle,
    this.errorMessage,
  });

  final {{name.pascalCase()}}Status status;
  final String? errorMessage;

  bool get isLoading => status == {{name.pascalCase()}}Status.loading;
  bool get hasError => status == {{name.pascalCase()}}Status.error;

  {{name.pascalCase()}}State copyWith({
    {{name.pascalCase()}}Status? status,
    String? errorMessage,
  }) {
    return {{name.pascalCase()}}State(
      status: status ?? this.status,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}
{{/useProvider}}
