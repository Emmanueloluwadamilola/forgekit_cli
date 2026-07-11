import 'package:awesome_dio_interceptor/awesome_dio_interceptor.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:injectable/injectable.dart';

/// Provides cross-cutting infrastructure singletons (Dio, secure storage, ...).
///
/// Registered automatically by injectable via [configureDependencies].
@module
abstract class CoreModule {
  /// Base URL for the backend API. Replace with your environment value.
  @Named('baseUrl')
  String get baseUrl => 'https://api.example.com';

  @lazySingleton
  FlutterSecureStorage get secureStorage => const FlutterSecureStorage();

  @lazySingleton
  Dio dio(@Named('baseUrl') String baseUrl) {
    final dio = Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 30),
        contentType: 'application/json',
      ),
    );

    dio.interceptors.add(AwesomeDioInterceptor());

    // TODO: add a 401/token-refresh interceptor here.

    return dio;
  }
}
