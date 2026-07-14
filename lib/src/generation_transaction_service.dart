import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;

class GenerationTransaction {
  GenerationTransaction._({
    required this.root,
    required this.command,
    required Map<String, _FileSnapshot> before,
  }) : _before = before;

  final Directory root;
  final String command;
  final Map<String, _FileSnapshot> _before;

  static Future<GenerationTransaction> begin({
    required Directory root,
    required String command,
  }) async {
    return GenerationTransaction._(
      root: root.absolute,
      command: command,
      before: await _snapshotProject(root),
    );
  }

  Future<List<GenerationChange>> finish({
    required bool success,
    required bool dryRun,
    required Logger logger,
    bool format = false,
  }) async {
    var after = await _snapshotProject(root);
    var changes = _compareSnapshots(_before, after);

    if (success && changes.isNotEmpty) {
      try {
        await _ensureForgeKitIgnored(root);
        after = await _snapshotProject(root);
        changes = _compareSnapshots(_before, after);
        if (format) {
          await _formatChangedDartFiles(root, changes);
          after = await _snapshotProject(root);
          changes = _compareSnapshots(_before, after);
        }
      } catch (error) {
        final current = await _snapshotProject(root);
        await _restoreSnapshot(root: root, before: _before, after: current);
        if (error is GenerationTransactionException) rethrow;
        throw GenerationTransactionException(
          'Could not prepare the generation transaction: $error',
        );
      }
    }

    if (!success || dryRun) {
      if (dryRun) {
        _printChanges(changes, logger, heading: 'Planned changes');
      }
      await _restoreSnapshot(root: root, before: _before, after: after);
      if (!success && changes.isNotEmpty) {
        logger.warn(
          'The command failed. Flutter ForgeKit CLI restored ${changes.length} project '
          'change(s).',
        );
      } else if (dryRun) {
        logger.info('Dry run complete. No project files were changed.');
      }
      return changes;
    }

    if (changes.isEmpty) return changes;
    await _recordTransaction(
      root: root,
      command: command,
      before: _before,
      after: after,
      changes: changes,
    );
    return changes;
  }
}

Future<void> _ensureForgeKitIgnored(Directory root) async {
  final file = File(p.join(root.path, '.gitignore'));
  final source = file.existsSync() ? await file.readAsString() : '';
  final entries =
      const LineSplitter().convert(source).map((line) => line.trim());
  if (entries.contains('.forgekit/') || entries.contains('.forgekit')) return;

  final buffer = StringBuffer(source);
  if (source.isNotEmpty && !source.endsWith('\n')) buffer.writeln();
  buffer.writeln('.forgekit/');
  await file.writeAsString(buffer.toString(), flush: true);
}

Future<void> _formatChangedDartFiles(
  Directory root,
  List<GenerationChange> changes,
) async {
  final paths = changes
      .where((change) => change.type != GenerationChangeType.deleted)
      .map((change) => change.path)
      .where((path) => path.endsWith('.dart'))
      .toList();
  if (paths.isEmpty) return;

  try {
    final result = await Process.run(
      'dart',
      ['format', ...paths],
      workingDirectory: root.path,
      runInShell: true,
    );
    if (result.exitCode != 0) {
      throw GenerationTransactionException(
        'Could not format generated Dart files:\n${result.stderr}',
      );
    }
  } on ProcessException catch (error) {
    throw GenerationTransactionException(
      'Could not start dart format: ${error.message}',
    );
  }
}

enum GenerationChangeType { created, modified, deleted }

class GenerationChange {
  const GenerationChange({
    required this.path,
    required this.type,
    this.beforeHash,
    this.afterHash,
    this.beforeLines,
    this.afterLines,
  });

  final String path;
  final GenerationChangeType type;
  final String? beforeHash;
  final String? afterHash;
  final int? beforeLines;
  final int? afterLines;

  Map<String, Object?> toJson() => {
        'path': path,
        'type': type.name,
        'beforeHash': beforeHash,
        'afterHash': afterHash,
        'beforeLines': beforeLines,
        'afterLines': afterLines,
      };

  factory GenerationChange.fromJson(Map<String, dynamic> json) {
    return GenerationChange(
      path: json['path'] as String,
      type: GenerationChangeType.values.byName(json['type'] as String),
      beforeHash: json['beforeHash'] as String?,
      afterHash: json['afterHash'] as String?,
      beforeLines: json['beforeLines'] as int?,
      afterLines: json['afterLines'] as int?,
    );
  }
}

class GenerationTransactionException implements Exception {
  const GenerationTransactionException(this.message);

  final String message;

  @override
  String toString() => message;
}

Future<int> showGenerationDiff({
  required Directory root,
  required Logger logger,
}) async {
  final transaction = await _loadLatestTransaction(root);
  if (transaction == null) {
    logger.info(
      'No Flutter ForgeKit CLI generation transaction has been recorded yet.',
    );
    return 0;
  }

  final changes = _changesFromTransaction(transaction);
  logger.info(
    'Latest transaction ${transaction['id']} '
    '(${transaction['command']}):',
  );
  var drifted = 0;
  for (final change in changes) {
    final file = File(p.join(root.path, change.path));
    final currentHash =
        file.existsSync() ? _hash(file.readAsBytesSync()) : null;
    final matches = currentHash == change.afterHash;
    if (!matches) drifted++;
    logger.info(
      '  ${matches ? 'unchanged' : 'changed  '}  ${change.path}',
    );
  }
  if (drifted == 0) {
    logger.success('No files have drifted since the latest generation.');
  } else {
    logger.warn('$drifted generated file(s) changed after generation.');
  }
  return drifted == 0 ? 0 : 1;
}

Future<int> rollbackLatestGeneration({
  required Directory root,
  required Logger logger,
  bool force = false,
}) async {
  final transaction = await _loadLatestTransaction(root);
  if (transaction == null) {
    logger.err(
      'No Flutter ForgeKit CLI generation transaction is available to roll back.',
    );
    return 1;
  }

  final id = transaction['id'] as String;
  final changes = _changesFromTransaction(transaction);
  final conflicts = <String>[];
  for (final change in changes) {
    final file = File(p.join(root.path, change.path));
    final currentHash =
        file.existsSync() ? _hash(file.readAsBytesSync()) : null;
    if (currentHash != change.afterHash) conflicts.add(change.path);
  }

  if (conflicts.isNotEmpty && !force) {
    logger.err(
      'Rollback stopped because ${conflicts.length} file(s) changed after '
      'generation:',
    );
    for (final path in conflicts) {
      logger.info('  $path');
    }
    logger.info('Review them first, or run "forgekit rollback --force".');
    return 1;
  }

  final backupRoot = Directory(
    p.join(root.path, '.forgekit', 'backups', id, 'before'),
  );
  for (final change in changes.reversed) {
    final target = File(p.join(root.path, change.path));
    if (change.type == GenerationChangeType.created) {
      if (target.existsSync()) await target.delete();
      continue;
    }

    final backup = File(p.join(backupRoot.path, change.path));
    if (!backup.existsSync()) {
      throw GenerationTransactionException(
        'Missing rollback backup for ${change.path}.',
      );
    }
    await target.parent.create(recursive: true);
    await _atomicWriteBytes(target, await backup.readAsBytes());
  }

  transaction['rolledBackAt'] = DateTime.now().toUtc().toIso8601String();
  await _writeJsonAtomic(
    File(p.join(root.path, '.forgekit', 'backups', id, 'transaction.json')),
    transaction,
  );

  final manifestFile = File(p.join(root.path, '.forgekit', 'manifest.json'));
  final manifest = await _readJsonMap(manifestFile) ?? <String, dynamic>{};
  manifest['latestTransaction'] = null;
  final generatedFiles = manifest['generatedFiles'];
  if (generatedFiles is Map) {
    for (final change in changes) {
      generatedFiles.remove(change.path);
    }
  }
  await _writeJsonAtomic(manifestFile, manifest);
  logger.success('Rolled back transaction $id (${changes.length} change(s)).');
  return 0;
}

Future<Map<String, _FileSnapshot>> _snapshotProject(Directory root) async {
  final files = <String, _FileSnapshot>{};
  if (!root.existsSync()) return files;
  await for (final entity in root.list(recursive: true, followLinks: false)) {
    if (entity is! File) continue;
    final relative = p.relative(entity.path, from: root.path);
    if (_ignored(relative)) continue;
    final bytes = await entity.readAsBytes();
    files[relative] = _FileSnapshot(
      bytes: bytes,
      hash: _hash(bytes),
      lines: _lineCount(bytes),
    );
  }
  return files;
}

bool _ignored(String relativePath) {
  final first = p.split(relativePath).first;
  return const {'.git', '.dart_tool', '.forgekit', 'build'}.contains(first);
}

List<GenerationChange> _compareSnapshots(
  Map<String, _FileSnapshot> before,
  Map<String, _FileSnapshot> after,
) {
  final paths = {...before.keys, ...after.keys}.toList()..sort();
  final changes = <GenerationChange>[];
  for (final path in paths) {
    final oldFile = before[path];
    final newFile = after[path];
    if (oldFile == null && newFile != null) {
      changes.add(
        GenerationChange(
          path: path,
          type: GenerationChangeType.created,
          afterHash: newFile.hash,
          afterLines: newFile.lines,
        ),
      );
    } else if (oldFile != null && newFile == null) {
      changes.add(
        GenerationChange(
          path: path,
          type: GenerationChangeType.deleted,
          beforeHash: oldFile.hash,
          beforeLines: oldFile.lines,
        ),
      );
    } else if (oldFile!.hash != newFile!.hash) {
      changes.add(
        GenerationChange(
          path: path,
          type: GenerationChangeType.modified,
          beforeHash: oldFile.hash,
          afterHash: newFile.hash,
          beforeLines: oldFile.lines,
          afterLines: newFile.lines,
        ),
      );
    }
  }
  return changes;
}

Future<void> _restoreSnapshot({
  required Directory root,
  required Map<String, _FileSnapshot> before,
  required Map<String, _FileSnapshot> after,
}) async {
  for (final path in after.keys.where((path) => !before.containsKey(path))) {
    final file = File(p.join(root.path, path));
    if (file.existsSync()) await file.delete();
  }
  for (final entry in before.entries) {
    final current = after[entry.key];
    if (current?.hash == entry.value.hash) continue;
    final file = File(p.join(root.path, entry.key));
    await file.parent.create(recursive: true);
    await _atomicWriteBytes(file, entry.value.bytes);
  }
}

Future<void> _recordTransaction({
  required Directory root,
  required String command,
  required Map<String, _FileSnapshot> before,
  required Map<String, _FileSnapshot> after,
  required List<GenerationChange> changes,
}) async {
  final now = DateTime.now().toUtc();
  final id = now
      .toIso8601String()
      .replaceAll(':', '')
      .replaceAll('.', '')
      .replaceAll('-', '');
  final transactionRoot = Directory(
    p.join(root.path, '.forgekit', 'backups', id),
  );
  final beforeRoot = Directory(p.join(transactionRoot.path, 'before'));
  await beforeRoot.create(recursive: true);

  for (final change in changes) {
    final oldFile = before[change.path];
    if (oldFile == null) continue;
    final backup = File(p.join(beforeRoot.path, change.path));
    await backup.parent.create(recursive: true);
    await backup.writeAsBytes(oldFile.bytes, flush: true);
  }

  final transaction = <String, Object?>{
    'version': 1,
    'id': id,
    'createdAt': now.toIso8601String(),
    'command': command,
    'changes': changes.map((change) => change.toJson()).toList(),
  };
  await _writeJsonAtomic(
    File(p.join(transactionRoot.path, 'transaction.json')),
    transaction,
  );

  final manifestFile = File(p.join(root.path, '.forgekit', 'manifest.json'));
  final manifest = await _readJsonMap(manifestFile) ??
      <String, dynamic>{
        'version': 1,
        'generatedFiles': <String, dynamic>{},
      };
  manifest['latestTransaction'] = id;
  final generatedFiles =
      (manifest['generatedFiles'] as Map?)?.cast<String, dynamic>() ??
          <String, dynamic>{};
  for (final change in changes) {
    if (change.type == GenerationChangeType.deleted) {
      generatedFiles.remove(change.path);
    } else {
      generatedFiles[change.path] = {
        'transaction': id,
        'hash': after[change.path]?.hash,
      };
    }
  }
  manifest['generatedFiles'] = generatedFiles;
  await _writeJsonAtomic(manifestFile, manifest);
}

Future<Map<String, dynamic>?> _loadLatestTransaction(Directory root) async {
  final manifest = await _readJsonMap(
    File(p.join(root.path, '.forgekit', 'manifest.json')),
  );
  final id = manifest?['latestTransaction'];
  if (id is! String || id.isEmpty) return null;
  return _readJsonMap(
    File(
      p.join(root.path, '.forgekit', 'backups', id, 'transaction.json'),
    ),
  );
}

List<GenerationChange> _changesFromTransaction(Map<String, dynamic> json) {
  final rawChanges = json['changes'];
  if (rawChanges is! List) {
    throw const GenerationTransactionException(
      'The Flutter ForgeKit CLI transaction is missing its change list.',
    );
  }
  return rawChanges
      .whereType<Map>()
      .map((item) => GenerationChange.fromJson(item.cast<String, dynamic>()))
      .toList();
}

void _printChanges(
  List<GenerationChange> changes,
  Logger logger, {
  required String heading,
}) {
  if (changes.isEmpty) {
    logger.info('$heading: none.');
    return;
  }
  logger.info('$heading (${changes.length}):');
  for (final change in changes) {
    final marker = switch (change.type) {
      GenerationChangeType.created => '+',
      GenerationChangeType.modified => '~',
      GenerationChangeType.deleted => '-',
    };
    final lineSummary = change.type == GenerationChangeType.modified
        ? ' (${change.beforeLines} -> ${change.afterLines} lines)'
        : '';
    logger.info('  $marker ${change.path}$lineSummary');
  }
}

Future<Map<String, dynamic>?> _readJsonMap(File file) async {
  if (!file.existsSync()) return null;
  try {
    final decoded = jsonDecode(await file.readAsString());
    return decoded is Map<String, dynamic> ? decoded : null;
  } on FormatException {
    throw GenerationTransactionException('Invalid JSON in ${file.path}.');
  }
}

Future<void> _writeJsonAtomic(File file, Map<String, Object?> value) async {
  await file.parent.create(recursive: true);
  final contents = '${const JsonEncoder.withIndent('  ').convert(value)}\n';
  final temporary = File('${file.path}.tmp');
  await temporary.writeAsString(contents, flush: true);
  if (file.existsSync()) await file.delete();
  await temporary.rename(file.path);
}

Future<void> _atomicWriteBytes(File file, List<int> bytes) async {
  final temporary = File('${file.path}.forgekit-tmp');
  await temporary.writeAsBytes(bytes, flush: true);
  if (file.existsSync()) await file.delete();
  await temporary.rename(file.path);
}

String _hash(List<int> bytes) => sha256.convert(bytes).toString();

int _lineCount(List<int> bytes) {
  try {
    final text = utf8.decode(bytes);
    if (text.isEmpty) return 0;
    return '\n'.allMatches(text).length + (text.endsWith('\n') ? 0 : 1);
  } on FormatException {
    return 0;
  }
}

class _FileSnapshot {
  const _FileSnapshot({
    required this.bytes,
    required this.hash,
    required this.lines,
  });

  final List<int> bytes;
  final String hash;
  final int lines;
}

/// Allows the global `--dry-run` flag to appear after subcommands.
List<String> normalizeDryRunOption(Iterable<String> arguments) {
  final args = arguments.toList();
  final remaining = <String>[];
  var found = false;
  for (var index = 0; index < args.length; index++) {
    final argument = args[index];
    if (argument == '--') {
      remaining.addAll(args.skip(index));
      break;
    }
    if (argument == '--dry-run') {
      if (found) {
        throw const FormatException('--dry-run can only be supplied once.');
      }
      found = true;
      continue;
    }
    remaining.add(argument);
  }
  return [if (found) '--dry-run', ...remaining];
}
