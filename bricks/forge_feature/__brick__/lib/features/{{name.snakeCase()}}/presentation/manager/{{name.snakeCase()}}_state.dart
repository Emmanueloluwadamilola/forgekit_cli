import 'package:{{projectName}}/core/presentation/manager/custom_state.dart';

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
