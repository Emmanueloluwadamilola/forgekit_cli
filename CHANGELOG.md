# Changelog

All notable changes to Flutter ForgeKit CLI are documented here. The project
uses semantic versioning while it remains pre-1.0; a minor-version change may
therefore contain a breaking CLI or generation-contract change.

## 0.1.0 - 2026-07-21

- Added Clean, MVVM, and Flutter Modular application and feature profiles.
- Added Provider, Riverpod, Bloc, and Cubit state-management variants.
- Added named-route, GoRouter, and Flutter Modular route generation.
- Added JSON model/function generation and OpenAPI 3.0/3.1 Clean feature
  import, including safe multi-document references, reusable operation
  components, composed schemas, scalar cookies, runtime security inputs and
  metadata, and generated DTO/model round-trip tests.
- Added generic, SharedPreferences, and secure-storage service generation with
  dependency-injection and startup wiring.
- Added project configuration, architecture checks, generated starter tests,
  workspace package targeting, dry runs, drift detection, and rollback.
- Added asset, font, localization, environment, flavor, launcher-icon, splash,
  reusable-widget, and Git-backed registry workflows.
- Added CLI unit tests and generated Flutter application smoke tests.
- Hardened bundled environment configuration by rejecting secret-like keys by
  default and adding `doctor` detection for existing files.
- Removed command arguments and option values from transaction metadata.
- Required full immutable commit SHAs for self-update and pinned the tested
  Mason CLI and GitHub Actions revisions.
- Added existing-target and path-traversal protection to app creation, with
  cleanup of incomplete destinations after handled failures.
- Made launcher-icon and splash generator failures propagate to the
  transaction instead of reporting false success.
- Removed shell mediation from Dart, Git, and Mason child-process execution,
  validated the remaining Windows Flutter batch arguments, and hardened
  organization identifiers.
- Rejected insecure or credential-bearing shared-registry remotes.
- Added strict architecture support guards so Clean-only semantic and feature
  lifecycle commands fail before prompting or writing in MVVM/Modular apps.
- Hardened JSON, asset, font, registry, transaction, and OpenAPI inputs,
  including HTTPS-only bounded downloads and opt-in remote OpenAPI references.
- Updated generated dependency baselines to versions resolved and smoke-tested
  with Flutter 3.44, including Riverpod 3 and SharedPreferencesAsync.
- Fixed multi-flavor Dart generation, mutable Provider operation state,
  Retrofit literal-dollar paths, and Dart 3.12 generated-code lints.
- Added cross-platform CLI CI, generated-project analysis/tests, and an Android
  debug build release gate.
- Made coverage enforcement fail closed when eligible production libraries are
  missing from Flutter's LCOV report.
- Prevented feature rename from changing API endpoint, JSON-key, deep-link, and
  other string-literal contracts.
- Fixed removal of named-route registrations wrapped across multiple lines by
  `dart format`.
- Restored newly created empty directories after failed, dry-run, and rolled
  back generation transactions.
- Required existing projects and source artifacts before starter widget,
  use-case, and standalone test generation.
- Made Lean and Legacy adoption-only profiles fail explicitly instead of
  falling through to Clean generation and repair behavior.
- Configured launcher icons only for native platforms present in the project.
- Serialized CLI test suites that mutate the process-wide working directory,
  and added format and executable-compilation CI gates.

This is the first Git-distributed public beta. Install the reviewed `v0.1.0`
release tag with Dart Pub's Git activation support; high-assurance automation
can pin the full commit SHA published with the release notes.
