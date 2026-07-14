import 'package:dio/dio.dart';
import 'package:retrofit/retrofit.dart';

part '{{name.snakeCase()}}_api_service.g.dart';

@RestApi()
abstract class {{name.pascalCase()}}ApiService {
  factory {{name.pascalCase()}}ApiService(Dio dio, {String baseUrl}) =
      _{{name.pascalCase()}}ApiService;
}
