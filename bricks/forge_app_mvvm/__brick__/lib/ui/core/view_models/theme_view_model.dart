import 'package:flutter/material.dart';
{{#useProvider}}import 'package:injectable/injectable.dart';
{{/useProvider}}{{#useRiverpod}}import 'package:flutter_riverpod/flutter_riverpod.dart';
{{/useRiverpod}}{{#useBloc}}import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';
{{/useBloc}}{{#useCubit}}import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';
{{/useCubit}}

{{#useProvider}}@injectable
class ThemeViewModel extends ChangeNotifier {
  ThemeMode _mode = ThemeMode.system;
  ThemeMode get mode => _mode;

  void setMode(ThemeMode mode) {
    if (_mode == mode) return;
    _mode = mode;
    notifyListeners();
  }
}
{{/useProvider}}{{#useRiverpod}}final themeViewModelProvider =
    NotifierProvider<ThemeViewModel, ThemeMode>(ThemeViewModel.new);

class ThemeViewModel extends Notifier<ThemeMode> {
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

@injectable
class ThemeViewModel extends Bloc<ThemeEvent, ThemeMode> {
  ThemeViewModel() : super(ThemeMode.system) {
    on<ThemeModeChanged>((event, emit) => emit(event.mode));
  }
}
{{/useBloc}}{{#useCubit}}@injectable
class ThemeViewModel extends Cubit<ThemeMode> {
  ThemeViewModel() : super(ThemeMode.system);
  void setMode(ThemeMode mode) => emit(mode);
}
{{/useCubit}}
