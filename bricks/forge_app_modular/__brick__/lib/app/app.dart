import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart' hide Consumer;
{{#useProvider}}import 'package:provider/provider.dart';
{{/useProvider}}{{#useRiverpod}}import 'package:flutter_riverpod/flutter_riverpod.dart';
{{/useRiverpod}}{{#useBloc}}import 'package:flutter_bloc/flutter_bloc.dart';
{{/useBloc}}{{#useCubit}}import 'package:flutter_bloc/flutter_bloc.dart';
{{/useCubit}}

import '../core/theme/app_theme.dart';
import '../core/theme/theme_controller.dart';

{{#useProvider}}class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
        create: (_) => ThemeController(),
        child: Consumer<ThemeController>(
          builder: (_, controller, __) =>
              _AppView(themeMode: controller.mode),
        ),
      );
}
{{/useProvider}}{{#useRiverpod}}class App extends ConsumerWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      _AppView(themeMode: ref.watch(themeControllerProvider));
}
{{/useRiverpod}}{{#useBloc}}class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider(
        create: (_) => ThemeController(),
        child: BlocBuilder<ThemeController, ThemeMode>(
          builder: (_, mode) => _AppView(themeMode: mode),
        ),
      );
}
{{/useBloc}}{{#useCubit}}class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider(
        create: (_) => ThemeController(),
        child: BlocBuilder<ThemeController, ThemeMode>(
          builder: (_, mode) => _AppView(themeMode: mode),
        ),
      );
}
{{/useCubit}}

class _AppView extends StatelessWidget {
  const _AppView({required this.themeMode});

  final ThemeMode themeMode;

  @override
  Widget build(BuildContext context) => MaterialApp.router(
        title: 'Flutter ForgeKit CLI Modular',
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: themeMode,
        routerConfig: ModularApp.routerConfigOf(context),
      );
}
