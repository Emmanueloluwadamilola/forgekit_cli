{{#useProvider}}import 'package:{{projectName}}/core/state/custom_provider.dart';
import 'package:{{projectName}}/modules/{{name.snakeCase()}}/presentation/{{name.snakeCase()}}_state.dart';

class {{name.pascalCase()}}Controller extends CustomProvider {
  final {{name.pascalCase()}}State _state = const {{name.pascalCase()}}State();
  {{name.pascalCase()}}State get state => _state;
}
{{/useProvider}}{{#useRiverpod}}import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:{{projectName}}/modules/{{name.snakeCase()}}/presentation/{{name.snakeCase()}}_state.dart';

final {{name.camelCase()}}ControllerProvider =
    NotifierProvider<{{name.pascalCase()}}Controller, {{name.pascalCase()}}State>(
  {{name.pascalCase()}}Controller.new,
);

class {{name.pascalCase()}}Controller extends Notifier<{{name.pascalCase()}}State> {
  @override
  {{name.pascalCase()}}State build() => const {{name.pascalCase()}}State();
}
{{/useRiverpod}}{{#useBloc}}import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:{{projectName}}/modules/{{name.snakeCase()}}/presentation/{{name.snakeCase()}}_state.dart';

sealed class {{name.pascalCase()}}Event {
  const {{name.pascalCase()}}Event();
}

// forgekit:event-classes

class {{name.pascalCase()}}Controller
    extends Bloc<{{name.pascalCase()}}Event, {{name.pascalCase()}}State> {
  {{name.pascalCase()}}Controller() : super(const {{name.pascalCase()}}State()) {
    // forgekit:event-registrations
  }
}
{{/useBloc}}{{#useCubit}}import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:{{projectName}}/modules/{{name.snakeCase()}}/presentation/{{name.snakeCase()}}_state.dart';

class {{name.pascalCase()}}Controller extends Cubit<{{name.pascalCase()}}State> {
  {{name.pascalCase()}}Controller() : super(const {{name.pascalCase()}}State());
}
{{/useCubit}}
