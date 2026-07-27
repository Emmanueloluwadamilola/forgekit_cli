import 'dart:convert';
import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';

import 'mason_environment.dart';

/// Mason CLI version tested with this ForgeKit release.
const supportedMasonCliVersion = '0.1.3';

/// Shared helpers used across the `forgekit` commands.

/// Converts a project-relative path to the portable form used in generated
/// metadata and user-facing reports.
String toPosixPath(String path) => path.replaceAll(r'\', '/');

/// Walks up from [start] (default: current directory) looking for the nearest
/// directory that contains a `pubspec.yaml`, i.e. the project root.
///
/// Returns `null` if none is found before reaching the filesystem root. This
/// lets `add`-style commands work whether they are run from the project root or
/// from somewhere inside `lib/features/<feature>/…`.
Directory? findProjectRoot([Directory? start]) {
  var dir = (start ?? Directory.current).absolute;
  while (true) {
    if (File(p.join(dir.path, 'pubspec.yaml')).existsSync()) return dir;
    final parent = dir.parent;
    if (parent.path == dir.path) return null; // hit the filesystem root
    dir = parent;
  }
}

/// Infers the feature name from the current location when the user has `cd`-ed
/// into `<root>/lib/features/<feature>/…`.
///
/// Returns `null` when [start] is not inside a specific feature folder (e.g. it
/// is the project root, or `lib/features` itself).
String? inferFeatureName({required Directory root, Directory? start}) {
  final current = (start ?? Directory.current).absolute.path;
  final featuresRoot = p.join(root.absolute.path, 'lib', 'features');
  if (!p.isWithin(featuresRoot, current)) return null;
  final rel = p.relative(current, from: featuresRoot);
  final first = p.split(rel).first;
  return first.isEmpty || first == '..' ? null : first;
}

/// Runs the `mason` executable with [args].
///
/// stdout and stderr from the child process are forwarded to this process so
/// the user sees Mason's own output. Returns the child process exit code.
///
/// If the `mason` executable cannot be found / started (e.g. it is not
/// installed), prints an actionable hint and returns `1`.
///
/// Pass [requiredBrick] when [args] invokes a bundled brick. On a non-zero exit
/// the brick's global registration is verified, so the common "never ran
/// `forgekit setup`" case reports that instead of leaving the caller to print a
/// bare "Failed to ..." message.
Future<int> runMason(
  List<String> args, {
  Logger? logger,
  String? workingDirectory,
  String? requiredBrick,
}) async {
  final log = logger ?? Logger();
  try {
    final result = await Process.start(
      'dart',
      ['pub', 'global', 'run', 'mason_cli:mason', ...args],
      workingDirectory: workingDirectory,
      // Inherit the parent's stdio so Mason prompts/output stream live.
      mode: ProcessStartMode.inheritStdio,
    );
    final exitCode = await result.exitCode;
    if (exitCode != 0 &&
        requiredBrick != null &&
        !isForgekitBrickRegistered(requiredBrick)) {
      logMissingBrickRegistration(logger: log, brick: requiredBrick);
    }
    return exitCode;
  } on ProcessException {
    log.err(
      'Could not run Mason CLI $supportedMasonCliVersion through Dart Pub. '
      'Run: forgekit setup',
    );
    return 1;
  }
}

/// Reports that a bundled brick is not registered with Mason, which means
/// `forgekit setup` has not completed for this installation.
void logMissingBrickRegistration({
  required Logger logger,
  required String brick,
}) {
  logger
    ..err('The bundled brick "$brick" is not registered with Mason.')
    ..err('Flutter ForgeKit CLI cannot generate code until setup completes.')
    ..info('')
    ..info('Run: forgekit setup');
}

/// Forces the value of [hasInteractiveTerminal]. For tests only; production
/// code never assigns it.
///
/// `dart test` runs the suite inside the test process, and `dart:io`'s terminal
/// state is process-global — so whether a suite sees a TTY depends on how it was
/// launched. Overriding the check keeps non-interactive tests deterministic
/// instead of passing in CI and hanging on a developer's machine.
bool? debugTerminalOverride;

/// Whether both stdin and stdout are attached to an interactive terminal.
///
/// Prompting without a terminal throws or blocks, so every interactive prompt
/// must be gated on this. CI jobs, container builds, and piped invocations all
/// report `false`.
bool get hasInteractiveTerminal =>
    debugTerminalOverride ?? (stdin.hasTerminal && stdout.hasTerminal);

/// Reports that a command needs values it can only obtain by prompting, and
/// lists the flags that supply them non-interactively.
///
/// [missing] entries should read as usage fragments, e.g.
/// `--architecture clean|mvvm|modular`.
void logMissingInteractiveInput({
  required Logger logger,
  required List<String> missing,
  String? invocation,
}) {
  final plural = missing.length != 1;
  logger
    ..err(
      'No interactive terminal is attached, so ForgeKit cannot prompt for '
      '${plural ? 'these values' : 'this value'}. '
      'Pass ${plural ? 'them' : 'it'} explicitly:',
    )
    ..err('');
  for (final flag in missing) {
    logger.err('  $flag');
  }
  if (invocation != null) {
    logger
      ..info('')
      ..info('Usage: $invocation');
  }
}

/// The lowest Dart SDK a generated Flutter ForgeKit CLI project can build with.
///
/// Kept in sync with the `environment: sdk:` constraint in every
/// `bricks/forge_app*/__brick__/pubspec.yaml`.
final minimumGeneratedProjectDartSdk = Version.parse('3.8.0');

/// The installed Flutter toolchain's reported versions.
class FlutterToolchain {
  const FlutterToolchain({
    required this.flutterVersion,
    required this.dartSdkVersion,
  });

  final String flutterVersion;
  final Version dartSdkVersion;
}

/// Reads the installed Flutter toolchain versions via
/// `flutter --version --machine`.
///
/// Returns `null` when Flutter is absent or its output cannot be parsed. A
/// `null` result is deliberately non-fatal: the caller reports the missing
/// toolchain when it actually shells out to `flutter`, and an unparseable
/// version must never block generation.
Future<FlutterToolchain?> readFlutterToolchain() async {
  final ProcessResult result;
  try {
    result = await Process.run(
      'flutter',
      ['--version', '--machine'],
      runInShell: Platform.isWindows,
    );
  } on ProcessException {
    return null;
  }
  if (result.exitCode != 0) return null;

  final output = result.stdout.toString();
  // Some setups prepend upgrade notices before the JSON payload.
  final start = output.indexOf('{');
  if (start == -1) return null;

  final Object? decoded;
  try {
    decoded = json.decode(output.substring(start));
  } on FormatException {
    return null;
  }
  if (decoded is! Map<String, dynamic>) return null;

  final dartSdk = decoded['dartSdkVersion'];
  if (dartSdk is! String) return null;
  // Flutter reports values such as "3.8.0" or "3.9.0 (build 3.9.0-100.2.beta)".
  final normalized = dartSdk.split(' ').first.trim();

  final Version parsed;
  try {
    parsed = Version.parse(normalized);
  } on FormatException {
    return null;
  }

  final frameworkVersion = decoded['frameworkVersion'];
  return FlutterToolchain(
    flutterVersion: frameworkVersion is String ? frameworkVersion : 'unknown',
    dartSdkVersion: parsed,
  );
}

/// Verifies the installed Flutter toolchain can build a generated project.
///
/// Returns `0` when compatible or undetectable, and `1` after reporting an
/// actionable upgrade message. Call this before any command that writes a
/// project from a bundled app brick, so the incompatibility surfaces before
/// files are created rather than as an opaque `pub get` failure afterwards.
Future<int> checkGeneratedProjectSdkSupport({required Logger logger}) async {
  final toolchain = await readFlutterToolchain();
  if (toolchain == null) return 0;

  if (toolchain.dartSdkVersion >= minimumGeneratedProjectDartSdk) return 0;

  logger
    ..err(
      'Flutter ${toolchain.flutterVersion} bundles Dart '
      '${toolchain.dartSdkVersion}, but a generated ForgeKit project requires '
      'Dart $minimumGeneratedProjectDartSdk or newer.',
    )
    ..err(
      'Generating now would produce a project that cannot resolve its '
      'dependencies.',
    )
    ..info('')
    ..info('Upgrade the toolchain, then retry:')
    ..info('  flutter upgrade');
  return 1;
}

/// Detects the Flutter/Dart project name by reading the `name:` field from the
/// `pubspec.yaml` in [root] (default: current directory).
///
/// Returns [fallback] (default `"app"`) when no pubspec exists or the field
/// cannot be parsed. This is intentionally a tiny hand-rolled parser so the CLI
/// does not depend on a full YAML package just for one field.
String detectProjectName({String fallback = 'app', Directory? root}) {
  final pubspec =
      File(p.join((root ?? Directory.current).path, 'pubspec.yaml'));
  if (!pubspec.existsSync()) return fallback;

  for (final rawLine in pubspec.readAsLinesSync()) {
    final line = rawLine.trim();
    // Skip comments and nested keys; the package name is a top-level `name:`.
    if (line.startsWith('#')) continue;
    if (!rawLine.startsWith('name:')) continue;

    var value = line.substring('name:'.length).trim();
    // Strip an inline comment, if any.
    final hashIndex = value.indexOf('#');
    if (hashIndex != -1) value = value.substring(0, hashIndex).trim();
    // Strip surrounding quotes.
    value = value.replaceAll('"', '').replaceAll("'", '').trim();
    if (value.isNotEmpty) return value;
  }
  return fallback;
}

/// Encodes literal dollar signs before a URL is passed to Retrofit's code
/// generator. Retrofit evaluates annotation constants and writes their values
/// into ordinary Dart string literals, where an unencoded `$` would become
/// unintended interpolation in the generated `.g.dart` file.
String encodeRetrofitUrlLiteral(String value) => value.replaceAll(r'$', '%24');
