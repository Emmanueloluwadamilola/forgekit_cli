import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:mason_logger/mason_logger.dart';

import '../workspace_service.dart';

class WorkspaceCommand extends Command<int> {
  WorkspaceCommand({Logger? logger}) : _logger = logger ?? Logger() {
    addSubcommand(_WorkspaceListCommand(logger: _logger));
  }

  final Logger _logger;

  @override
  String get name => 'workspace';

  @override
  String get description => 'Inspect packages in a Dart pub workspace.';
}

class _WorkspaceListCommand extends Command<int> {
  _WorkspaceListCommand({Logger? logger}) : _logger = logger ?? Logger() {
    argParser.addFlag(
      'json',
      negatable: false,
      help: 'Print the workspace package list as JSON.',
    );
  }

  final Logger _logger;

  @override
  String get name => 'list';

  @override
  String get description => 'List every package in the current workspace.';

  @override
  Future<int> run() async {
    try {
      final workspace = await discoverPubWorkspace();
      if (argResults!['json'] as bool) {
        final output = {
          'root': workspace.root.path,
          'packages': workspace.packages
              .map(
                (package) => {
                  'name': package.name,
                  'path': workspace.relativePath(package),
                  'flutter': package.isFlutter,
                },
              )
              .toList(),
        };
        stdout.writeln(const JsonEncoder.withIndent('  ').convert(output));
        return 0;
      }

      _logger.info('Workspace: ${workspace.root.path}');
      for (final package in workspace.packages) {
        final type = package.isFlutter ? 'Flutter' : 'Dart';
        _logger.info(
          '  ${package.name.padRight(24)} '
          '${workspace.relativePath(package).padRight(32)} $type',
        );
      }
      return 0;
    } on WorkspaceException catch (error) {
      _logger.err(error.message);
      return 1;
    }
  }
}
