import 'package:forgekit/src/json_to_dart.dart';
import 'package:test/test.dart';

void main() {
  test('escapes keywords and JSON keys in generated DTO source', () {
    final classes = analyzeJson('Account', {
      'class': 'admin',
      r"owner's $token": 'value',
    });

    final source = emitDto(classes, partName: 'account_dto');

    expect(source, contains('final String classValue;'));
    expect(source, contains(r'@JsonKey(name: "class")'));
    expect(source, contains(r'''@JsonKey(name: "owner's \$token")'''));
  });

  test('rejects JSON keys that normalize to the same Dart field', () {
    expect(
      () => analyzeJson('Account', {
        'user-id': 1,
        'user_id': 2,
      }),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects invalid class names and heterogeneous arrays', () {
    expect(
      () => analyzeJson('123', {'value': 1}),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => analyzeJson('Account', {
        'values': [1, 'two'],
      }),
      throwsA(isA<FormatException>()),
    );
  });

  test('widens mixed integer and double arrays to num', () {
    final classes = analyzeJson('Metrics', {
      'values': [1, 2.5],
    });

    expect(classes.last.fields.single.modelType, 'List<num>');
  });

  test('rejects inconsistent top-level object samples', () {
    expect(
      () => analyzeJsonObjects('Account', [
        {'id': 1, 'name': 'Ada'},
        {'id': 2},
      ]),
      throwsA(isA<FormatException>()),
    );
  });
}
