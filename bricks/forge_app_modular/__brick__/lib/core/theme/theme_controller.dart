import 'package:flutter/material.dart';
{{#useRiverpod}}import 'package:flutter_riverpod/flutter_riverpod.dart';
{{/useRiverpod}}{{#useBloc}}import 'package:flutter_bloc/flutter_bloc.dart';
{{/useBloc}}{{#useCubit}}import 'package:flutter_bloc/flutter_bloc.dart';
{{/useCubit}}

{{#useProvider}}class ThemeController extends ChangeNotifier {
  ThemeMode _mode = ThemeMode.system;
  ThemeMode get mode => _mode;

  void setMode(ThemeMode mode) {
    if (_mode == mode) return;
    _mode = mode;
    notifyListeners();
  }
}
{{/useProvider}}{{#useRiverpod}}final themeControllerProvider =
    NotifierProvider<ThemeController, ThemeMode>(ThemeController.new);

class ThemeController extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ThemeMode.system;

  void setMode(ThemeMode mode) => state = mode;
}
{{/useRiverpod}}{{#useBloc}}sealed class ThemeEvent {
  const ThemeEvent();
}

class ThemeModeChanged extends ThemeEvent {
  const ThemeModeChanged(this.mode);

  final ThemeMode mode;
}

class ThemeController extends Bloc<ThemeEvent, ThemeMode> {
  ThemeController() : super(ThemeMode.system) {
    on<ThemeModeChanged>((event, emit) => emit(event.mode));
  }
}
{{/useBloc}}{{#useCubit}}class ThemeController extends Cubit<ThemeMode> {
  ThemeController() : super(ThemeMode.system);

  void setMode(ThemeMode mode) => emit(mode);
}
{{/useCubit}}
