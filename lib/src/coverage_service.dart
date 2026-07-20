import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;

import 'config_service.dart';

const _generatedDartSuffixes = <String>[
  '.config.dart',
  '.freezed.dart',
  '.g.dart',
  '.gr.dart',
  '.mocks.dart',
];

typedef FlutterTestExecutor = Future<int> Function(
  Directory workingDirectory,
  List<String> arguments,
);

/// Runs Flutter tests and enforces the line-coverage threshold configured in
/// `forgekit.yaml`.
Future<int> runProjectTests({
  required Directory root,
  required Logger logger,
  required ForgeKitConfig config,
  bool collectCoverage = true,
  List<String> flutterTestArguments = const [],
  FlutterTestExecutor? executor,
}) async {
  if (Platform.isWindows &&
      executor == null &&
      flutterTestArguments.any(hasUnsafeWindowsBatchCharacters)) {
    logger.err(
      'A forwarded Flutter test argument contains characters that are unsafe '
      'for the Windows flutter.bat command wrapper. Remove shell control '
      'characters and retry.',
    );
    return 64;
  }

  String? coverageArgument;
  for (final argument in flutterTestArguments) {
    if (argument.startsWith('--coverage')) {
      coverageArgument = argument;
      break;
    }
  }
  if (coverageArgument != null) {
    logger.err(
      'Coverage options are owned by ForgeKit. Remove "$coverageArgument" '
      'and use forgekit.yaml testing.coverage.',
    );
    return 64;
  }

  final reportFile = File(p.join(root.path, 'coverage', 'lcov.info'));
  try {
    if (collectCoverage && reportFile.existsSync()) {
      await reportFile.delete();
    }
  } on FileSystemException catch (error) {
    logger.err(
      'Could not remove the previous coverage report: ${error.message}',
    );
    return 1;
  }

  final arguments = <String>[
    'test',
    if (collectCoverage) '--coverage',
    ...flutterTestArguments,
  ];
  logger.info('Running: flutter ${arguments.join(' ')}');

  final int testExitCode;
  try {
    testExitCode = await (executor ?? _executeFlutterTests)(root, arguments);
  } on ProcessException catch (error) {
    logger
      ..err('Could not start Flutter tests: ${error.message}')
      ..info('Install Flutter and ensure `flutter` is available on PATH.');
    return 1;
  }

  if (testExitCode != 0) {
    logger.err('Flutter tests failed with exit code $testExitCode.');
    return testExitCode;
  }
  if (!collectCoverage) {
    logger.success('Flutter tests passed. Coverage collection was disabled.');
    return 0;
  }
  if (!reportFile.existsSync()) {
    logger.err(
      'Flutter tests passed, but coverage/lcov.info was not generated. '
      'The configured coverage threshold cannot be verified.',
    );
    return 1;
  }

  final CoverageSummary summary;
  try {
    summary = parseLcov(
      await reportFile.readAsString(),
      projectRoot: root,
    );
  } on FileSystemException catch (error) {
    logger.err('Could not read coverage/lcov.info: ${error.message}');
    return 1;
  } on CoverageException catch (error) {
    logger.err('Invalid coverage report: ${error.message}');
    return 1;
  }

  if (summary.totalLines == 0) {
    logger.err(
      'Coverage report contains no executable lines under lib/. '
      'Add tests that load production source before enforcing a threshold.',
    );
    return 1;
  }
  if (summary.unreportedFiles.isNotEmpty) {
    final preview = summary.unreportedFiles.take(8).join(', ');
    final remaining = summary.unreportedFiles.length - 8;
    logger.err(
      'Coverage report omitted ${summary.unreportedFiles.length} eligible '
      'production file(s): $preview${remaining > 0 ? ', and $remaining more' : ''}. '
      'Add tests that load these libraries or explicitly exclude generated '
      'outputs using ForgeKit-supported suffixes.',
    );
    return 1;
  }

  final actual = summary.percentage;
  final required = config.minimumCoverage.toDouble();
  final details = '${summary.coveredLines}/${summary.totalLines} lines';
  if (actual + 1e-9 < required) {
    logger.err(
      'Coverage ${actual.toStringAsFixed(2)}% ($details) is below the '
      'configured ${config.minimumCoverage}% threshold.',
    );
    return 1;
  }

  logger.success(
    'Coverage ${actual.toStringAsFixed(2)}% ($details) meets the '
    'configured ${config.minimumCoverage}% threshold.',
  );
  return 0;
}

/// Whether an argument could be interpreted as control syntax by `cmd.exe`
/// when Windows launches Flutter's batch wrapper.
bool hasUnsafeWindowsBatchCharacters(String argument) {
  return RegExp(r'''[&|<>^%!()"\r\n]''').hasMatch(argument);
}

Future<int> _executeFlutterTests(
  Directory workingDirectory,
  List<String> arguments,
) async {
  final process = await Process.start(
    'flutter',
    arguments,
    workingDirectory: workingDirectory.path,
    mode: ProcessStartMode.inheritStdio,
    runInShell: Platform.isWindows,
  );
  return process.exitCode;
}

/// Parses an LCOV report and computes unique executable-line coverage for
/// production Dart source under `lib/`.
///
/// Generated Dart files are excluded because they are compiler inputs/outputs,
/// not application code owned by the project. Duplicate records are merged by
/// source path and line number so merged LCOV files cannot inflate totals.
CoverageSummary parseLcov(
  String source, {
  required Directory projectRoot,
}) {
  final libRoot = _canonicalPath(p.absolute(projectRoot.path, 'lib'));
  final lineHits = <String, int>{};
  final reportedSources = <String>{};
  String? currentSource;

  final lines = source.split(RegExp(r'\r?\n'));
  for (var index = 0; index < lines.length; index++) {
    final line = lines[index].trim();
    if (line.isEmpty) continue;

    if (line.startsWith('SF:')) {
      final rawPath = line.substring(3).trim();
      if (rawPath.isEmpty) {
        throw CoverageException('empty SF record at line ${index + 1}.');
      }
      currentSource = _normalizeSourcePath(rawPath, projectRoot);
      if (p.isWithin(libRoot, currentSource) &&
          !_isGeneratedDartFile(currentSource)) {
        reportedSources.add(currentSource);
      }
      continue;
    }
    if (line == 'end_of_record') {
      currentSource = null;
      continue;
    }
    if (!line.startsWith('DA:')) continue;
    if (currentSource == null) {
      throw CoverageException(
        'DA record without a preceding SF record at line ${index + 1}.',
      );
    }

    final values = line.substring(3).split(',');
    if (values.length < 2) {
      throw CoverageException('malformed DA record at line ${index + 1}.');
    }
    final lineNumber = int.tryParse(values[0]);
    final hits = int.tryParse(values[1]);
    if (lineNumber == null || lineNumber <= 0 || hits == null || hits < 0) {
      throw CoverageException('invalid DA record at line ${index + 1}.');
    }

    final normalizedSource = currentSource;
    if (!p.isWithin(libRoot, normalizedSource)) continue;
    if (_isGeneratedDartFile(normalizedSource)) continue;

    final key = '$normalizedSource:$lineNumber';
    final existing = lineHits[key];
    if (existing == null || hits > existing) lineHits[key] = hits;
  }

  final missingSources = <String>[];
  final canonicalProjectRoot = _canonicalPath(projectRoot.path);
  final libDirectory = Directory(libRoot);
  if (libDirectory.existsSync()) {
    for (final entity
        in libDirectory.listSync(recursive: true, followLinks: false)) {
      if (entity is! File || p.extension(entity.path) != '.dart') continue;
      final sourcePath = _canonicalPath(entity.path);
      if (_isGeneratedDartFile(sourcePath) ||
          reportedSources.contains(sourcePath)) {
        continue;
      }
      missingSources.add(p.relative(sourcePath, from: canonicalProjectRoot));
    }
  }
  missingSources.sort();

  return CoverageSummary(
    coveredLines: lineHits.values.where((hits) => hits > 0).length,
    totalLines: lineHits.length,
    unreportedFiles: missingSources,
  );
}

String _normalizeSourcePath(String source, Directory projectRoot) {
  if (source.startsWith('file:')) {
    try {
      return _canonicalPath(Uri.parse(source).toFilePath());
    } on FormatException {
      throw CoverageException('invalid source URI "$source".');
    } on UnsupportedError {
      throw CoverageException('invalid source URI "$source".');
    }
  }
  return _canonicalPath(
    p.absolute(
      p.isAbsolute(source) ? source : p.join(projectRoot.path, source),
    ),
  );
}

String _canonicalPath(String path) {
  final normalized = p.normalize(path);
  try {
    return File(normalized).resolveSymbolicLinksSync();
  } on FileSystemException {
    return normalized;
  }
}

bool _isGeneratedDartFile(String path) =>
    _generatedDartSuffixes.any(path.endsWith);

class CoverageSummary {
  const CoverageSummary({
    required this.coveredLines,
    required this.totalLines,
    this.unreportedFiles = const [],
  });

  final int coveredLines;
  final int totalLines;
  final List<String> unreportedFiles;

  double get percentage =>
      totalLines == 0 ? 0 : coveredLines * 100 / totalLines;
}

class CoverageException implements Exception {
  const CoverageException(this.message);

  final String message;

  @override
  String toString() => message;
}
