import 'dart:io';

import 'package:forgekit/forgekit.dart';

/// The `forgekit` executable entrypoint.
///
/// Delegates all argument handling to [ForgeCommandRunner] and propagates the
/// resulting exit code back to the shell.
Future<void> main(List<String> args) async {
  final exitCode = await ForgeCommandRunner().run(args);
  exit(exitCode);
}
