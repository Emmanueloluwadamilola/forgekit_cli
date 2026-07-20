import 'dart:io';

import 'package:forgekit/src/openapi_service.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('parseOpenApi', () {
    test('parses tagged operations, parameters, bodies, and responses', () {
      final document = parseOpenApi(r'''
openapi: 3.0.3
info:
  title: Store API
  version: 1.0.0
servers:
  - url: https://api.example.com/v1
paths:
  /users/{userId}:
    parameters:
      - name: userId
        in: path
        required: true
        schema:
          type: string
    put:
      operationId: updateUser
      summary: Update one user
      tags: [Users]
      parameters:
        - name: verbose
          in: query
          schema:
            type: boolean
      requestBody:
        required: true
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/UserInput'
      responses:
        '200':
          description: Updated
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/User'
components:
  schemas:
    UserInput:
      type: object
      required: [name]
      properties:
        name:
          type: string
    User:
      allOf:
        - $ref: '#/components/schemas/UserInput'
        - type: object
          required: [id]
          properties:
            id:
              type: integer
''');

      expect(document.version, '3.0.3');
      expect(document.title, 'Store API');
      expect(document.serverUrl, 'https://api.example.com/v1');
      expect(document.operations, hasLength(1));

      final operation = document.operations.single;
      expect(operation.name, 'update_user');
      expect(operation.method, 'PUT');
      expect(operation.path, '/users/{userId}');
      expect(operation.tags, ['Users']);
      expect(operation.parameters, hasLength(2));
      expect(operation.parameters.first.required, isTrue);
      expect(operation.requestRequired, isTrue);
      expect(
        operation.requestSchema?[r'$ref'],
        '#/components/schemas/UserInput',
      );
      expect(operation.responseStatus, '200');
      expect(operation.responseSchema?[r'$ref'], '#/components/schemas/User');
    });

    test('supports JSON, generated operation names, and default responses', () {
      final document = parseOpenApi(r'''
{
  "openapi": "3.1.0",
  "info": {"title": "Health", "version": "1"},
  "paths": {
    "/health": {
      "get": {
        "responses": {
          "default": {
            "description": "status",
            "content": {
              "application/problem+json": {
                "schema": {"type": "string"}
              }
            }
          }
        }
      }
    }
  }
}
''');

      final operation = document.operations.single;
      expect(operation.name, 'get_health');
      expect(operation.responseStatus, 'default');
      expect(operation.responseSchema?['type'], 'string');
    });

    test('rejects Swagger 2 documents', () {
      expect(
        () => parseOpenApi('swagger: "2.0"\npaths: {}'),
        throwsA(
          isA<OpenApiException>().having(
            (error) => error.message,
            'message',
            contains('OpenAPI 3.0 or 3.1'),
          ),
        ),
      );
    });

    test('rejects plaintext HTTP entry documents before downloading', () async {
      await expectLater(
        loadOpenApiDocument('http://example.com/openapi.yaml'),
        throwsA(
          isA<OpenApiException>().having(
            (error) => error.message,
            'message',
            contains('require HTTPS'),
          ),
        ),
      );
    });

    test('rejects OpenAPI 3.1 JSON Schema base URI changes', () {
      expect(
        () => parseOpenApi(r'''
openapi: 3.1.1
info: {title: IDs, version: '1'}
paths:
  /value:
    get:
      responses:
        '200':
          description: value
          content:
            application/json:
              schema:
                $id: ./other-schema.json
                type: object
'''),
        throwsA(isA<OpenApiException>()),
      );
    });

    test('loads external references and reusable operation components',
        () async {
      final root = Directory.systemTemp.createTempSync('forgekit_openapi_');
      addTearDown(() => root.deleteSync(recursive: true));
      File(p.join(root.path, 'schemas.yaml')).writeAsStringSync(r'''
UserInput:
  type: object
  required: [name]
  properties:
    name: {type: string}
User:
  allOf:
    - $ref: '#/UserInput'
    - type: object
      required: [id]
      properties:
        id: {type: integer}
''');
      final entry = File(p.join(root.path, 'openapi.yaml'))
        ..writeAsStringSync(r'''
openapi: 3.1.1
info: {title: External API, version: '1'}
components:
  securitySchemes:
    bearerAuth:
      type: http
      scheme: bearer
      bearerFormat: JWT
  parameters:
    UserId:
      name: userId
      in: path
      required: true
      schema: {type: string}
    TraceId:
      name: X-Trace-Id
      in: header
      schema: {type: string}
  requestBodies:
    UserBody:
      required: true
      content:
        application/json:
          schema: {$ref: 'schemas.yaml#/UserInput'}
  responses:
    UserResponse:
      description: Updated user
      content:
        application/json:
          schema: {$ref: 'schemas.yaml#/User'}
security:
  - bearerAuth: []
paths:
  /users/{userId}:
    parameters:
      - $ref: '#/components/parameters/UserId'
    put:
      operationId: updateUser
      parameters:
        - $ref: '#/components/parameters/TraceId'
      requestBody:
        $ref: '#/components/requestBodies/UserBody'
      responses:
        '200':
          $ref: '#/components/responses/UserResponse'
''');

      final document = await loadOpenApiDocument(entry.path);
      final operation = document.operations.single;

      expect(operation.parameters.map((value) => value.name), [
        'userId',
        'X-Trace-Id',
      ]);
      expect(operation.requestRequired, isTrue);
      expect(document.resolve(operation.requestSchema!)['type'], 'object');
      expect(
        document.resolve(operation.responseSchema!)['allOf'],
        isA<List<dynamic>>(),
      );
      expect(document.securitySchemes['bearerAuth']?.scheme, 'bearer');
      expect(operation.security.single.schemes, {'bearerAuth': <String>[]});
    });

    test('operation security can explicitly allow anonymous access', () {
      final document = parseOpenApi(r'''
openapi: 3.0.3
info: {title: Auth API, version: '1'}
components:
  securitySchemes:
    apiKey:
      type: apiKey
      name: X-API-Key
      in: header
security:
  - apiKey: []
paths:
  /public:
    get:
      security: []
      responses:
        '204': {description: No content}
''');

      expect(document.defaultSecurity, hasLength(1));
      expect(document.operations.single.security, isEmpty);
    });

    test('parses scalar cookie parameters for generated Cookie headers', () {
      final document = parseOpenApi(r'''
openapi: 3.0.3
info: {title: Cookie API, version: '1'}
paths:
  /profile:
    get:
      parameters:
        - name: locale
          in: cookie
          schema: {type: string}
      responses:
        '204': {description: No content}
''');

      final parameter = document.operations.single.parameters.single;
      expect(parameter.name, 'locale');
      expect(parameter.location, 'cookie');
      expect(parameter.required, isFalse);
    });

    test('expands server defaults, 2XX responses, and 3.1 ref siblings', () {
      final document = parseOpenApi(r'''
openapi: 3.1.1
info: {title: Modern API, version: '1'}
servers:
  - url: https://{region}.example.com/{version}
    variables:
      region: {default: eu}
      version: {default: v2}
components:
  schemas:
    Identifier: {type: string}
paths:
  /value:
    get:
      responses:
        2XX:
          description: Value
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/Identifier'
                nullable: true
''');

      expect(document.serverUrl, 'https://eu.example.com/v2');
      expect(document.operations.single.responseStatus, '2XX');
      expect(document.resolve(document.operations.single.responseSchema!), {
        'type': 'string',
        'nullable': true,
      });
    });

    test('rejects non-JSON bodies instead of silently mis-generating them', () {
      expect(
        () => parseOpenApi(r'''
openapi: 3.1.1
info: {title: Upload API, version: '1'}
paths:
  /upload:
    post:
      requestBody:
        content:
          multipart/form-data:
            schema: {type: object}
      responses:
        '204': {description: No content}
'''),
        throwsA(
          isA<OpenApiException>().having(
            (error) => error.message,
            'message',
            contains('multipart/form-data'),
          ),
        ),
      );
    });

    test('rejects local references that escape the entry directory', () async {
      final parent = Directory.systemTemp.createTempSync('forgekit_openapi_');
      addTearDown(() => parent.deleteSync(recursive: true));
      File(p.join(parent.path, 'outside.yaml')).writeAsStringSync('{}');
      final child = Directory(p.join(parent.path, 'api'))..createSync();
      final entry = File(p.join(child.path, 'openapi.yaml'))
        ..writeAsStringSync(r'''
openapi: 3.1.1
info: {title: Unsafe, version: '1'}
paths:
  /value:
    get:
      responses:
        '200':
          description: Value
          content:
            application/json:
              schema: {$ref: '../outside.yaml#/Value'}
''');

      await expectLater(
        loadOpenApiDocument(entry.path),
        throwsA(
          isA<OpenApiException>().having(
            (error) => error.message,
            'message',
            contains('escapes the entry document directory'),
          ),
        ),
      );
    });

    test('local documents require opt-in before fetching remote references',
        () async {
      final directory =
          Directory.systemTemp.createTempSync('forgekit_openapi_remote_ref_');
      addTearDown(() => directory.deleteSync(recursive: true));
      final entry = File(p.join(directory.path, 'openapi.yaml'))
        ..writeAsStringSync(r'''
openapi: 3.1.1
info: {title: Remote ref, version: '1'}
paths:
  /value:
    get:
      responses:
        '200':
          description: Value
          content:
            application/json:
              schema: {$ref: 'https://example.com/schema.yaml#/Value'}
''');

      await expectLater(
        loadOpenApiDocument(entry.path),
        throwsA(
          isA<OpenApiException>().having(
            (error) => error.message,
            'message',
            contains('may not fetch remote references by default'),
          ),
        ),
      );
    });

    test('rejects conflicting object union property types', () {
      expect(
        () => parseOpenApi(r'''
openapi: 3.1.1
info: {title: Conflict, version: '1'}
paths:
  /value:
    get:
      responses:
        '200':
          description: Value
          content:
            application/json:
              schema:
                oneOf:
                  - type: object
                    properties: {id: {type: integer}}
                  - type: object
                    properties: {id: {type: string}}
'''),
        throwsA(isA<OpenApiException>()),
      );
    });
  });
}
