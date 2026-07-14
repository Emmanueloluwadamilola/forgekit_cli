import 'package:dio/dio.dart';
import 'package:injectable/injectable.dart';

@module
abstract class CoreModule {
  @lazySingleton
  Dio dio() => Dio();
}
