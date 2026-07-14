import 'package:flutter/material.dart';
{{#useProvider}}import 'package:injectable/injectable.dart';
{{/useProvider}}{{#useRiverpod}}import 'package:flutter_riverpod/flutter_riverpod.dart';
{{/useRiverpod}}{{#useBloc}}import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';
{{/useBloc}}{{#useCubit}}import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';
{{/useCubit}}

{{#useProvider}}@injectable
class ThemeProvider extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.system;

  ThemeMode get themeMode => _themeMode;

  void setThemeMode(ThemeMode mode) {
    if (_themeMode == mode) return;
    _themeMode = mode;
    notifyListeners();
  }
}
{{/useProvider}}{{#useRiverpod}}final themeProvider =
    NotifierProvider<ThemeController, ThemeMode>(ThemeController.new);

class ThemeController extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ThemeMode.system;

  void setThemeMode(ThemeMode mode) => state = mode;
}
{{/useRiverpod}}{{#useBloc}}sealed class ThemeEvent {
  const ThemeEvent();
}

class ThemeModeChanged extends ThemeEvent {
  const ThemeModeChanged(this.mode);

  final ThemeMode mode;
}

@injectable
class ThemeBloc extends Bloc<ThemeEvent, ThemeMode> {
  ThemeBloc() : super(ThemeMode.system) {
    on<ThemeModeChanged>((event, emit) => emit(event.mode));
  }
}
{{/useBloc}}{{#useCubit}}@injectable
class ThemeCubit extends Cubit<ThemeMode> {
  ThemeCubit() : super(ThemeMode.system);

  void setThemeMode(ThemeMode mode) => emit(mode);
}
{{/useCubit}}
