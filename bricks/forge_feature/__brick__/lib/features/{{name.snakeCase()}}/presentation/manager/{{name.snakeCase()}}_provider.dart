{{#useProvider}}import 'package:injectable/injectable.dart';

import 'package:{{projectName}}/core/presentation/manager/custom_provider.dart';
import 'package:{{projectName}}/features/{{name.snakeCase()}}/presentation/manager/{{name.snakeCase()}}_state.dart';

@injectable
class {{name.pascalCase()}}Provider extends CustomProvider {
  {{name.pascalCase()}}State _state = const {{name.pascalCase()}}State();
  {{name.pascalCase()}}State get state => _state;
}
{{/useProvider}}{{#useRiverpod}}import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:{{projectName}}/features/{{name.snakeCase()}}/presentation/manager/{{name.snakeCase()}}_state.dart';

final {{name.camelCase()}}Provider = NotifierProvider<{{name.pascalCase()}}Notifier, {{name.pascalCase()}}State>(
  {{name.pascalCase()}}Notifier.new,
);

class {{name.pascalCase()}}Notifier extends Notifier<{{name.pascalCase()}}State> {
  @override
  {{name.pascalCase()}}State build() => const {{name.pascalCase()}}State();
}
{{/useRiverpod}}{{#useBloc}}import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';

import 'package:{{projectName}}/features/{{name.snakeCase()}}/presentation/manager/{{name.snakeCase()}}_state.dart';

sealed class {{name.pascalCase()}}Event {
  const {{name.pascalCase()}}Event();
}

// forgekit:event-classes

@injectable
class {{name.pascalCase()}}Bloc extends Bloc<{{name.pascalCase()}}Event, {{name.pascalCase()}}State> {
  {{name.pascalCase()}}Bloc() : super(const {{name.pascalCase()}}State()) {
    // forgekit:event-registrations
  }
}
{{/useBloc}}{{#useCubit}}import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';

import 'package:{{projectName}}/features/{{name.snakeCase()}}/presentation/manager/{{name.snakeCase()}}_state.dart';

@injectable
class {{name.pascalCase()}}Cubit extends Cubit<{{name.pascalCase()}}State> {
  {{name.pascalCase()}}Cubit() : super(const {{name.pascalCase()}}State());
}
{{/useCubit}}
