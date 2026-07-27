# Contributing to Flutter ForgeKit CLI

Thanks for helping improve ForgeKit. The project is a Git-distributed public
beta, so focused bug fixes, cross-platform corrections, documentation
improvements, and well-tested generator additions are especially useful.

## Before opening a change

1. Search existing issues and open a proposal before starting a large command,
   architecture profile, or generated-code contract.
2. Do not include credentials, private application code, or customer data.
   Report security issues through the private process in
   [SECURITY.md](SECURITY.md).
3. Keep changes narrow. Avoid mixing a generator behavior change with unrelated
   formatting or refactoring.

## Local setup

```sh
dart pub get
dart run bin/forgekit.dart setup
dart run bin/forgekit.dart --help
```

The setup command replaces global Mason registrations named `forge_*` with the
bundled copies from this checkout.

## Required quality checks

Run these before opening a pull request:

```sh
dart format --output=none --set-exit-if-changed bin lib test tool
dart analyze
dart test
dart compile exe bin/forgekit.dart -o /tmp/forgekit
```

`dart pub publish --dry-run` is deliberately not in that list: `pubspec.yaml`
sets `publish_to: none`, so `pub publish` refuses to run at all.

Do not run `dart format .`: raw Mason templates contain Mustache expressions and
are not valid Dart until rendered.

Changes to bricks, architecture routing, dependencies, startup wiring, or
generated tests must also run at least the affected generated-app smoke case:

```sh
dart run tool/generated_app_smoke.dart --case clean_provider_named
```

Run all four representative cases before merging broad generator changes:

```sh
dart run tool/generated_app_smoke.dart
```

## Tests and safety expectations

- Add a regression test for every bug fix when practical.
- Test failure paths before file creation as well as the success path.
- File-writing commands must refuse unsupported architectures and missing source
  artifacts before creating directories.
- Destructive operations must be transactional, preserve user-authored code, and
  require explicit confirmation or a force flag.
- Network inputs must use bounded downloads and secure transports.
- Keep macOS, Linux, and Windows path and process behavior in mind.

## Pull requests

Describe the user-visible behavior, the commands you ran, and any limitations
that could not be tested locally. Call out changes to command behavior,
generated file structure, file-write logic, configuration, or public APIs so
reviewers can focus on compatibility and rollback safety.
