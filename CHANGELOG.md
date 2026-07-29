# Changelog

All notable changes to Flutter ForgeKit CLI are documented here. The project
uses semantic versioning while it remains pre-1.0; a minor-version change may
therefore contain a breaking CLI or generation-contract change.

## Unreleased

Added:

- `forgekit add firebase --features crashlytics,analytics,push,remote_config`
  generates fully implemented Crashlytics, Analytics, Cloud Messaging, and
  Remote Config services, registers them in dependency injection, adds the
  version-pinned packages, and inserts `Firebase.initializeApp` ahead of the
  dependency graph. Omitting `--features` in a terminal opens a multi-select;
  in CI the flag is required.
  - Services initialize in a fixed order — crashlytics, analytics, push,
    remote_config — regardless of argument order, so the Crashlytics error
    handlers are installed before any later service can throw.
  - Crashlytics disables reporting in debug builds and installs both
    `FlutterError.onError` and `PlatformDispatcher.instance.onError`.
  - Analytics exposes a single `FirebaseAnalyticsObserver`; ForgeKit reports
    how to attach it rather than guessing the insertion point per router.
  - Every generated `init()` guards on `defaultTargetPlatform` and returns
    early on a platform the plugin does not implement. `create app` offers
    Windows and Linux, where an unguarded call would throw
    `MissingPluginException` before `runApp` and abort startup.
  - `--features backend` is parsed and rejected with an explanatory message.
    Firebase as a backend is not implemented yet.
  - The command requires `lib/firebase_options.dart` and directs the developer
    to `flutterfire configure` when it is missing, rather than generating code
    that references a class which does not exist.
  - Initialization is idempotent, so adding a second capability later does not
    duplicate the call.
  - Documented as §6.1 of the Architecture Standard.
- `doctor` reports a project that depends on `firebase_core` but is missing
  `lib/firebase_options.dart`, the `Firebase.initializeApp` call, or the
  Android/iOS native config files. It also reports a `firebase_crashlytics`
  dependency without the `com.google.firebase.crashlytics` Gradle plugin, which
  otherwise fails silently.

- `create app`, `add function`, and `add model` now detect the absence of an
  interactive terminal and report the flags that replace each prompt, instead of
  throwing or blocking in CI, container builds, and piped invocations.
- `create app` and `doctor` verify the installed Flutter toolchain against the
  generated-project Dart SDK floor before writing anything.
- `doctor` reports bundled bricks that Mason has no registration for, so a
  skipped `forgekit setup` is named rather than surfacing later as a bare
  "Failed to add feature".
- Mason failures for a bundled brick now check that brick's registration and
  point at `forgekit setup` when it is missing.
- Generated applications now ship a `.gitignore` (including `.forgekit/` and
  `coverage/`), a `README.md`, a GitHub Actions CI workflow, and a starter test,
  so a new project has a passing suite and a working CI run from its first
  commit. The workflow's formatting gate is commented out until the bundled
  templates are reformatted for the tall style.
- Added `test/command_runner_e2e_test.dart`, which drives `ForgeCommandRunner`
  end to end with the terminal check forced off, so any command that reaches an
  unguarded prompt now fails the build.

- `forgekit uninstall` removes everything `setup` installed in one command:
  the global Mason brick registrations, `~/.forgekit`, and the executable —
  in that order, because unregistering after deleting the brick directories
  leaves Mason's global config pointing at paths that no longer exist.
  - `--dry-run` prints the plan and changes nothing; the same list is shown
    before the confirmation prompt.
  - `--keep-widgets` preserves the synced widget library, the one
    irreplaceable thing in the data directory.
  - `--remove-mason` is opt-in: `setup` only installs Mason when it is absent,
    so ForgeKit cannot tell whether it owns it.
  - `--clean-project` removes `forgekit.yaml` and `.forgekit/` from the current
    project only. It never searches the filesystem.
  - Refuses to delete a filesystem root, an immediate child of one, or the home
    directory, so a stray `FORGEKIT_HOME` cannot escalate into `rm -rf ~`.
  - Requires `--force` in a non-interactive shell rather than prompting.
  - Self-deactivation runs last and degrades gracefully on Windows, where a
    running executable cannot be deleted.
- `doc/UNINSTALL.md` documents the command, its options, and the manual
  equivalent for when `forgekit` itself will not run.

Fixed:

- `add model` explains that JSON must be piped in when no terminal is attached.
- Removed `dart pub publish --dry-run` from the required contributor checks; it
  cannot run against `publish_to: none`.

Internal:

- Extracted brick-set, ForgeKit-home, and Mason-cache resolution into
  `lib/src/mason_environment.dart`, shared by setup and the new checks.
- All terminal detection now goes through `hasInteractiveTerminal`, which tests
  override via `debugTerminalOverride`.

Known follow-up:

- The CLI's own SDK floor stays at `>=3.5.4` even though generated projects need
  `>=3.8.0`, because raising it moves the package past language version 3.7 and
  switches `dart format` to the tall style, requiring a tree-wide reformat. The
  mismatch is enforced at runtime instead. Reformatting `lib`, `test`, `tool`,
  and every `__brick__` template, then raising the floor and re-enabling both
  formatting gates, is a single self-contained change.

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
