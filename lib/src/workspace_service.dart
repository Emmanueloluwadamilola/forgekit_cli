import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// A package reported by `dart pub workspace list`.
class WorkspacePackage {
  const WorkspacePackage({
    required this.name,
    required this.directory,
    required this.isFlutter,
  });

  final String name;
  final Directory directory;
  final bool isFlutter;
}

/// A Dart pub workspace and all packages participating in its resolution.
class PubWorkspace {
  const PubWorkspace({
    required this.root,
    required this.packages,
  });

  final Directory root;
  final List<WorkspacePackage> packages;

  /// Resolves [selector] as a package name or a path relative to the workspace.
  WorkspacePackage resolvePackage(String selector, {bool flutterOnly = true}) {
    final value = selector.trim();
    if (value.isEmpty) {
      throw const WorkspaceException('The workspace package cannot be empty.');
    }

    final nameMatches = packages.where((package) => package.name == value);
    WorkspacePackage? match;
    if (nameMatches.length == 1) {
      match = nameMatches.single;
    } else {
      final selectedPath = _resolvedDirectoryPath(
        p.isAbsolute(value) ? value : p.join(root.path, value),
      );
      final pathMatches = packages.where(
        (package) => p.equals(
          _resolvedDirectoryPath(package.directory.path),
          selectedPath,
        ),
      );
      if (pathMatches.length == 1) match = pathMatches.single;
    }

    if (match == null) {
      final choices = packages
          .where((package) => !flutterOnly || package.isFlutter)
          .map((package) => package.name)
          .join(', ');
      throw WorkspaceException(
        'No workspace package matches "$selector".'
        '${choices.isEmpty ? '' : ' Available packages: $choices.'}',
      );
    }

    if (flutterOnly && !match.isFlutter) {
      throw WorkspaceException(
        'Workspace package "${match.name}" is not a Flutter package. '
        'Flutter ForgeKit CLI project commands must target a Flutter package.',
      );
    }
    return match;
  }

  String relativePath(WorkspacePackage package) {
    final relative = p.relative(package.directory.path, from: root.path);
    return relative == '.' ? '.' : p.normalize(relative);
  }
}

class WorkspaceException implements Exception {
  const WorkspaceException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Uses Pub's own workspace resolver so nested workspaces and SDK-supported
/// glob syntax behave exactly like `dart pub workspace list`.
Future<PubWorkspace> discoverPubWorkspace({Directory? start}) async {
  final workingDirectory = (start ?? Directory.current).absolute;
  final ProcessResult result;
  try {
    result = await Process.run(
      'dart',
      ['pub', 'workspace', 'list', '--json'],
      workingDirectory: workingDirectory.path,
    );
  } on ProcessException catch (error) {
    throw WorkspaceException(
      'Could not start Dart to inspect the workspace: ${error.message}',
    );
  }

  if (result.exitCode != 0) {
    final details = result.stderr.toString().trim();
    throw WorkspaceException(
      details.isEmpty
          ? 'No Dart pub workspace was found from ${workingDirectory.path}.'
          : details,
    );
  }

  final Object? decoded;
  try {
    decoded = jsonDecode(result.stdout.toString());
  } on FormatException {
    throw const WorkspaceException(
      'Dart returned an invalid response while listing workspace packages.',
    );
  }

  if (decoded is! Map<String, dynamic> || decoded['packages'] is! List) {
    throw const WorkspaceException(
      'Dart returned an unexpected workspace package list.',
    );
  }

  final packages = <WorkspacePackage>[];
  for (final entry in decoded['packages'] as List) {
    if (entry is! Map || entry['name'] is! String || entry['path'] is! String) {
      throw const WorkspaceException(
        'Dart returned an invalid package in the workspace package list.',
      );
    }
    final rawPath = entry['path'] as String;
    final directory = Directory(
      p.isAbsolute(rawPath) ? rawPath : p.join(workingDirectory.path, rawPath),
    ).absolute;
    packages.add(
      WorkspacePackage(
        name: entry['name'] as String,
        directory: directory,
        isFlutter: _isFlutterPackage(directory),
      ),
    );
  }

  if (packages.isEmpty) {
    throw const WorkspaceException('The Dart pub workspace has no packages.');
  }

  final rootPackages = packages
      .where(
        (candidate) => packages.every(
          (package) =>
              p.equals(candidate.directory.path, package.directory.path) ||
              p.isWithin(candidate.directory.path, package.directory.path),
        ),
      )
      .toList();
  if (rootPackages.isEmpty) {
    throw const WorkspaceException(
      'Could not determine the Dart pub workspace root.',
    );
  }

  final declaredRoots = rootPackages
      .where((package) => _declaresWorkspace(package.directory))
      .toList();
  if (declaredRoots.isEmpty) {
    throw WorkspaceException(
      'No Dart pub workspace was found from ${workingDirectory.path}. '
      'Add a workspace entry to the repository pubspec.yaml first.',
    );
  }

  packages.sort((a, b) {
    final pathCompare = a.directory.path.compareTo(b.directory.path);
    return pathCompare != 0 ? pathCompare : a.name.compareTo(b.name);
  });
  return PubWorkspace(
    root: declaredRoots.first.directory,
    packages: List.unmodifiable(packages),
  );
}

bool _declaresWorkspace(Directory directory) {
  final pubspec = File(p.join(directory.path, 'pubspec.yaml'));
  if (!pubspec.existsSync()) return false;
  try {
    final yaml = loadYaml(pubspec.readAsStringSync());
    return yaml is YamlMap && yaml.containsKey('workspace');
  } on YamlException {
    return false;
  }
}

String _resolvedDirectoryPath(String path) {
  try {
    return Directory(path).resolveSymbolicLinksSync();
  } on FileSystemException {
    return p.canonicalize(path);
  }
}

bool _isFlutterPackage(Directory directory) {
  final pubspec = File(p.join(directory.path, 'pubspec.yaml'));
  if (!pubspec.existsSync()) return false;

  try {
    final yaml = loadYaml(pubspec.readAsStringSync());
    if (yaml is! YamlMap) return false;
    if (yaml.containsKey('flutter')) return true;
    final dependencies = yaml['dependencies'];
    return dependencies is YamlMap && dependencies.containsKey('flutter');
  } on YamlException {
    return false;
  }
}

/// Allows the global `--package` option to appear anywhere in a command.
///
/// The `args` package normally requires global options before the command name.
/// Moving only this known option keeps invocations such as
/// `forgekit add feature auth --package mobile_app` ergonomic without changing
/// the order of any subcommand arguments.
List<String> normalizePackageOption(Iterable<String> arguments) {
  final args = arguments.toList();
  final packageTokens = <String>[];
  final remaining = <String>[];
  var found = false;

  for (var index = 0; index < args.length; index++) {
    final argument = args[index];
    if (argument == '--') {
      remaining.addAll(args.skip(index));
      break;
    }
    if (argument == '--package') {
      if (found) {
        throw const FormatException('--package can only be supplied once.');
      }
      if (index + 1 >= args.length) {
        throw const FormatException('Missing value for --package.');
      }
      found = true;
      packageTokens.addAll([argument, args[++index]]);
      continue;
    }
    if (argument.startsWith('--package=')) {
      if (found) {
        throw const FormatException('--package can only be supplied once.');
      }
      if (argument.substring('--package='.length).trim().isEmpty) {
        throw const FormatException('Missing value for --package.');
      }
      found = true;
      packageTokens.add(argument);
      continue;
    }
    remaining.add(argument);
  }

  return [...packageTokens, ...remaining];
}
