import 'package:forgekit/src/openapi_service.dart';
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
            contains('OpenAPI 3.x'),
          ),
        ),
      );
    });
  });
}
