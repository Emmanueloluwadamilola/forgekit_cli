import 'package:flutter/material.dart';
{{#useProvider}}import 'package:provider/provider.dart';
{{/useProvider}}{{#useRiverpod}}import 'package:flutter_riverpod/flutter_riverpod.dart';
{{/useRiverpod}}{{#useBloc}}import 'package:flutter_bloc/flutter_bloc.dart';
{{/useBloc}}{{#useCubit}}import 'package:flutter_bloc/flutter_bloc.dart';
{{/useCubit}}

import 'package:{{projectName}}/core/state/view_state.dart';
import 'package:{{projectName}}/modules/{{name.snakeCase()}}/presentation/{{name.snakeCase()}}_controller.dart';
import 'package:{{projectName}}/modules/{{name.snakeCase()}}/presentation/{{name.snakeCase()}}_state.dart';

{{#useProvider}}class {{name.pascalCase()}}Page extends StatelessWidget {
{{/useProvider}}{{#useRiverpod}}class {{name.pascalCase()}}Page extends ConsumerWidget {
{{/useRiverpod}}{{#useBloc}}class {{name.pascalCase()}}Page extends StatelessWidget {
{{/useBloc}}{{#useCubit}}class {{name.pascalCase()}}Page extends StatelessWidget {
{{/useCubit}}  const {{name.pascalCase()}}Page({super.key});

  @override
{{#useRiverpod}}  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch({{name.camelCase()}}ControllerProvider);
    return _{{name.pascalCase()}}View(state: state);
  }
{{/useRiverpod}}{{^useRiverpod}}  Widget build(BuildContext context) {
{{#useProvider}}    return ChangeNotifierProvider(
      create: (_) => {{name.pascalCase()}}Controller(),
      child: Consumer<{{name.pascalCase()}}Controller>(
        builder: (_, controller, _) =>
            _{{name.pascalCase()}}View(state: controller.state),
      ),
    );
{{/useProvider}}{{#useBloc}}    return BlocProvider(
      create: (_) => {{name.pascalCase()}}Controller(),
      child: BlocBuilder<{{name.pascalCase()}}Controller, {{name.pascalCase()}}State>(
        builder: (_, state) => _{{name.pascalCase()}}View(state: state),
      ),
    );
{{/useBloc}}{{#useCubit}}    return BlocProvider(
      create: (_) => {{name.pascalCase()}}Controller(),
      child: BlocBuilder<{{name.pascalCase()}}Controller, {{name.pascalCase()}}State>(
        builder: (_, state) => _{{name.pascalCase()}}View(state: state),
      ),
    );
{{/useCubit}}  }
{{/useRiverpod}}}

class _{{name.pascalCase()}}View extends StatelessWidget {
  const _{{name.pascalCase()}}View({required this.state});

  final {{name.pascalCase()}}State state;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('{{name.titleCase()}}')),
        body: switch (state.status) {
          ViewStatus.loading =>
            const Center(child: CircularProgressIndicator()),
          ViewStatus.error => Center(
              child: Text(state.errorMessage ?? 'Something went wrong'),
            ),
          _ => const SizedBox.shrink(),
        },
      );
}
