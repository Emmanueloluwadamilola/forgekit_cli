{{#useProvider}}import 'package:injectable/injectable.dart';

import 'package:{{projectName}}/ui/core/view_models/custom_provider.dart';
import 'package:{{projectName}}/ui/{{name.snakeCase()}}/view_models/{{name.snakeCase()}}_state.dart';

@injectable
class {{name.pascalCase()}}ViewModel extends CustomProvider {
  final {{name.pascalCase()}}State _state = const {{name.pascalCase()}}State();
  {{name.pascalCase()}}State get state => _state;
}
{{/useProvider}}{{#useRiverpod}}import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:{{projectName}}/ui/{{name.snakeCase()}}/view_models/{{name.snakeCase()}}_state.dart';

final {{name.camelCase()}}ViewModelProvider =
    NotifierProvider<{{name.pascalCase()}}ViewModel, {{name.pascalCase()}}State>(
  {{name.pascalCase()}}ViewModel.new,
);

class {{name.pascalCase()}}ViewModel extends Notifier<{{name.pascalCase()}}State> {
  @override
  {{name.pascalCase()}}State build() => const {{name.pascalCase()}}State();
}
{{/useRiverpod}}{{#useBloc}}import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';

import 'package:{{projectName}}/ui/{{name.snakeCase()}}/view_models/{{name.snakeCase()}}_state.dart';

sealed class {{name.pascalCase()}}Event {
  const {{name.pascalCase()}}Event();
}

// forgekit:event-classes

@injectable
class {{name.pascalCase()}}ViewModel
    extends Bloc<{{name.pascalCase()}}Event, {{name.pascalCase()}}State> {
  {{name.pascalCase()}}ViewModel() : super(const {{name.pascalCase()}}State()) {
    // forgekit:event-registrations
  }
}
{{/useBloc}}{{#useCubit}}import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';

import 'package:{{projectName}}/ui/{{name.snakeCase()}}/view_models/{{name.snakeCase()}}_state.dart';

@injectable
class {{name.pascalCase()}}ViewModel extends Cubit<{{name.pascalCase()}}State> {
  {{name.pascalCase()}}ViewModel() : super(const {{name.pascalCase()}}State());
}
{{/useCubit}}
