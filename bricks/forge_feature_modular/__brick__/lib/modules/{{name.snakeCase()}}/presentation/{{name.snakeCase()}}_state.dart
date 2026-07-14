import 'package:{{projectName}}/core/state/view_state.dart';

class {{name.pascalCase()}}State extends ViewState {
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
