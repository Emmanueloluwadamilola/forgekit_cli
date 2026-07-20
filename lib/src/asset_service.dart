import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';
import 'package:yaml_edit/yaml_edit.dart';

import 'config_service.dart';
import 'json_to_dart.dart';

/// Adds an asset — a single file **or a whole folder** — to the project:
/// copies it in (when the source is outside the project), registers its
/// folder(s) under `flutter > assets:` in `pubspec.yaml`, and generates typed
/// constants in `lib/core/presentation/resources/drawables.dart`.
///
/// Returns `0` on success, `1` on failure.
Future<int> addAsset({
  required String sourcePath,
  required Logger logger,
  required Directory root,
  String? dir,
  bool recursive = false,
}) async {
  String? normalizedDir;
  try {
    normalizedDir = dir == null ? null : _normalizeAssetSubdirectory(dir);
  } on _AssetException catch (error) {
    logger.err(error.message);
    return 1;
  }
  if (FileSystemEntity.isDirectorySync(sourcePath)) {
    return _addAssetFolder(
      Directory(sourcePath),
      logger: logger,
      root: root,
      dir: normalizedDir,
      recursive: recursive,
    );
  }
  if (!File(sourcePath).existsSync()) {
    logger.err('Source not found: $sourcePath');
    return 1;
  }
  return _addAssetFile(
    File(sourcePath),
    logger: logger,
    root: root,
    dir: normalizedDir,
  );
}

// ---------------------------------------------------------------------------
// Single file
// ---------------------------------------------------------------------------

Future<int> _addAssetFile(
  File src, {
  required Logger logger,
  required Directory root,
  String? dir,
}) async {
  final fileName = p.basename(src.path);
  final sub = dir ?? _defaultSubdir(p.extension(fileName).toLowerCase());
  final assetPath = 'assets/$sub/$fileName';
  final assetsRoot = p.normalize(p.absolute(root.path, 'assets'));
  final destAbs = p.normalize(p.join(assetsRoot, sub, fileName));
  if (!p.isWithin(assetsRoot, destAbs)) {
    logger.err('Asset destination escapes the project assets directory.');
    return 1;
  }

  final progress = logger.progress('Adding asset "$fileName"');
  final Drawables result;
  final bool copied;
  try {
    final destFile = File(destAbs);
    // Never overwrite what already exists — only copy when absent.
    copied = !destFile.existsSync();
    if (copied) {
      destFile.parent.createSync(recursive: true);
      src.copySync(destAbs);
    }
    _registerAssetDir(root, 'assets/$sub/');
    result = _addDrawableConstants(root, [
      (name: _constName(fileName), assetPath: assetPath),
    ]);
  } on _AssetException catch (e) {
    progress.fail(e.message);
    return 1;
  }
  progress.complete('Added asset "$fileName".');

  logger
    ..info('')
    ..info(
      copied
          ? '  copied  → $assetPath'
          : '  file    → $assetPath (already exists, kept)',
    )
    ..info('  pubspec → assets/$sub/')
    ..info(
      '  const   → Drawables.${_constName(fileName)}'
      '${result.added > 0 ? '' : ' (already present)'}',
    )
    ..info('')
    ..info('Next steps:')
    ..info('  flutter pub get');
  return 0;
}

// ---------------------------------------------------------------------------
// Folder (batch)
// ---------------------------------------------------------------------------

Future<int> _addAssetFolder(
  Directory srcDir, {
  required Logger logger,
  required Directory root,
  String? dir,
  required bool recursive,
}) async {
  final files = _collectFiles(srcDir, recursive);
  if (files.isEmpty) {
    logger.err('No files found in ${srcDir.path}'
        '${recursive ? '' : ' (try --recursive for nested folders)'}.');
    return 1;
  }

  // When the folder already lives inside the project we generate constants for
  // the files where they are; otherwise we copy them under assets/<sub>/.
  final inProject = p.isWithin(root.absolute.path, srcDir.absolute.path);
  final sub = dir ?? p.basename(srcDir.path);

  final progress = logger.progress(
    'Adding ${files.length} asset(s) from "${p.basename(srcDir.path)}"',
  );

  final entries = <({String name, String assetPath})>[];
  final dirsToRegister = <String>{};
  var copiedCount = 0;
  var existedCount = 0;

  try {
    for (final f in files) {
      final fileName = p.basename(f.path);
      final String assetPath;
      if (inProject) {
        assetPath = _posix(p.relative(f.path, from: root.absolute.path));
      } else {
        final relFromSrc = p.relative(f.path, from: srcDir.path);
        final destRel = p.normalize(p.join('assets', sub, relFromSrc));
        final destFile = File(p.join(root.path, destRel));
        final assetsRoot = p.normalize(p.absolute(root.path, 'assets'));
        if (!p.isWithin(assetsRoot, p.normalize(destFile.absolute.path))) {
          throw const _AssetException(
            'Asset destination escapes the project assets directory.',
          );
        }
        // Never overwrite what already exists — only copy when absent.
        if (destFile.existsSync()) {
          existedCount++;
        } else {
          destFile.parent.createSync(recursive: true);
          f.copySync(destFile.path);
          copiedCount++;
        }
        assetPath = _posix(destRel);
      }
      dirsToRegister.add('${_posix(p.dirname(assetPath))}/');
      entries.add((name: _constName(fileName), assetPath: assetPath));
    }

    for (final d in dirsToRegister) {
      _registerAssetDir(root, d);
    }
    final result = _addDrawableConstants(root, entries);
    progress.complete(
      'Added ${result.added} constant(s) from "${p.basename(srcDir.path)}".',
    );

    final filesLine = inProject
        ? '${files.length} (in place)'
        : '${files.length} (copied $copiedCount'
            '${existedCount > 0 ? ', $existedCount already existed' : ''})';
    logger
      ..info('')
      ..info('  files    : $filesLine')
      ..info('  pubspec  : registered ${dirsToRegister.length} folder(s)')
      ..info('  constants: ${result.added} added'
          '${result.skipped > 0 ? ', ${result.skipped} already present' : ''}');
    if (result.collisions.isNotEmpty) {
      logger.warn(
        '  skipped duplicate name(s): ${result.collisions.join(', ')} '
        '(two files map to the same constant — rename one).',
      );
    }
    logger
      ..info('')
      ..info('Next steps:')
      ..info('  flutter pub get');
    return 0;
  } on _AssetException catch (e) {
    progress.fail(e.message);
    return 1;
  }
}

/// Lists the files directly in [dir] (or recursively), skipping hidden files
/// such as `.DS_Store`.
List<File> _collectFiles(Directory dir, bool recursive) {
  return dir
      .listSync(recursive: recursive)
      .whereType<File>()
      .where((f) => !p.basename(f.path).startsWith('.'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
}

String _posix(String path) => path.replaceAll(r'\', '/');

String _normalizeAssetSubdirectory(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty ||
      p.isAbsolute(trimmed) ||
      p.posix.isAbsolute(trimmed) ||
      p.windows.isAbsolute(trimmed)) {
    throw const _AssetException(
      '--dir must be a non-empty relative directory below assets/.',
    );
  }
  final segments = trimmed.split(RegExp(r'[/\\]+'));
  if (segments.any(
    (segment) =>
        segment.isEmpty ||
        segment == '.' ||
        segment == '..' ||
        segment.contains(':') ||
        segment.contains(RegExp(r'[\x00-\x1F]')),
  )) {
    throw const _AssetException(
      '--dir must not contain traversal, drive, or control-character segments.',
    );
  }
  return p.joinAll(segments);
}

String _defaultSubdir(String ext) {
  const images = {'.png', '.jpg', '.jpeg', '.gif', '.webp', '.bmp', '.svg'};
  const anim = {'.json', '.lottie'};
  if (images.contains(ext)) return 'images';
  if (anim.contains(ext)) return 'lottie';
  return 'files';
}

/// A valid Dart identifier derived from the file name (without extension).
String _constName(String fileName) {
  final camel = camelCase(p.basenameWithoutExtension(fileName));
  return camel.isEmpty ? 'asset' : camel;
}

/// Adds [assetDir] (e.g. `assets/images/`) to `flutter > assets:` if absent.
void _registerAssetDir(Directory root, String assetDir) {
  final pubspec = File(p.join(root.path, 'pubspec.yaml'));
  if (!pubspec.existsSync()) {
    throw const _AssetException('No pubspec.yaml at the project root.');
  }
  final editor = YamlEditor(pubspec.readAsStringSync());

  final existing = _tryParse(editor, ['flutter', 'assets']);
  final current = existing is YamlList
      ? existing.map((e) => e.toString()).toList()
      : <String>[];
  if (current.contains(assetDir)) return; // already registered
  final merged = [...current, assetDir];

  if (_tryParse(editor, ['flutter']) == null) {
    editor.update(['flutter'], {'assets': merged});
  } else {
    editor.update(['flutter', 'assets'], merged);
  }
  pubspec.writeAsStringSync(editor.toString());
}

/// Result of a batch constant insert.
typedef Drawables = ({int added, int skipped, List<String> collisions});

/// Creates or extends the `Drawables` constants class with [entries], skipping
/// names already present in the file or duplicated within the batch. Reads and
/// writes the file once.
Drawables _addDrawableConstants(
  Directory root,
  List<({String name, String assetPath})> entries,
) {
  final file = File(
    p.joinAll([
      root.path,
      ..._drawablePath(loadForgeKitConfig(root: root)),
    ]),
  );
  final existingContent = file.existsSync() ? file.readAsStringSync() : null;

  final present = <String>{};
  if (existingContent != null) {
    for (final m
        in RegExp(r'static const (\w+)\s*=').allMatches(existingContent)) {
      present.add(m.group(1)!);
    }
  }

  final seen = <String>{};
  final toAdd = <({String name, String assetPath})>[];
  var skipped = 0;
  final collisions = <String>[];
  for (final e in entries) {
    if (present.contains(e.name)) {
      skipped++;
      continue;
    }
    if (!seen.add(e.name)) {
      collisions.add(e.name);
      continue;
    }
    toAdd.add(e);
  }

  if (toAdd.isEmpty) {
    return (added: 0, skipped: skipped, collisions: collisions);
  }

  final lines = toAdd
      .map(
        (e) =>
            "  static const ${e.name} = '${_escapeDartString(e.assetPath)}';",
      )
      .join('\n');

  if (existingContent == null) {
    file.parent.createSync(recursive: true);
    file.writeAsStringSync('''
/// Typed asset paths. Maintained by `forgekit add asset`.
class Drawables {
  Drawables._();

$lines
}
''');
  } else {
    final idx = existingContent.lastIndexOf('}');
    if (idx == -1) {
      throw const _AssetException(
        'drawables.dart has no class body to extend.',
      );
    }
    file.writeAsStringSync(
      '${existingContent.substring(0, idx)}$lines\n${existingContent.substring(idx)}',
    );
  }
  return (added: toAdd.length, skipped: skipped, collisions: collisions);
}

List<String> _drawablePath(ForgeKitConfig config) =>
    switch (config.architecture) {
      'mvvm' => const ['lib', 'ui', 'core', 'resources', 'drawables.dart'],
      'modular' => const ['lib', 'core', 'resources', 'drawables.dart'],
      _ => const [
          'lib',
          'core',
          'presentation',
          'resources',
          'drawables.dart',
        ],
    };

String _escapeDartString(String value) => value
    .replaceAll(r'\', r'\\')
    .replaceAll("'", r"\'")
    .replaceAll(r'$', r'\$');

YamlNode? _tryParse(YamlEditor editor, List<Object?> path) {
  try {
    return editor.parseAt(path);
  } on ArgumentError {
    return null;
  }
}

class _AssetException implements Exception {
  const _AssetException(this.message);
  final String message;
}
