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

    // Add application-owned authentication, redacted debug logging, retry, and
    // token-refresh interceptors here. ForgeKit deliberately does not install a
    // body/header logger because generated release builds must not disclose
    // credentials or private API payloads by default.

    return dio;
  }
}
