# Flutter ForgeKit CLI

> A local Dart CLI for building Flutter applications with repeatable project
> structure, selectable architecture profiles, and generator-backed workflows.

The product name is **Flutter ForgeKit CLI**. Its executable and all terminal
commands remain `forgekit`.

Flutter ForgeKit CLI helps software teams turn a Flutter architecture standard
into consistent, executable commands. Instead of manually copying folders,
renaming files, wiring dependencies, and recreating the same feature patterns,
developers can scaffold apps, features, API operations, models, screens,
widgets, services, assets, flavors, launch icons, and splash screens from one
CLI.

Under the hood, Flutter ForgeKit CLI combines Mason bricks with native Dart
generators. Brick-backed commands create known project structures, while Dart
generators parse JSON, update YAML, write strongly typed Dart code, and wire
generated files into the existing application. This keeps code generation
predictable, reviewable, and aligned with the Flutter ForgeKit CLI Architecture
Standard.

Flutter ForgeKit CLI is local-first. It does not require an account, API key,
or cloud service. Commands run with the same network and filesystem access as
the current terminal process, including commands that download Google Fonts or
run package tools.

## Features

- Scaffold a complete Flutter app from the `forge_app` Mason brick.
- Choose Clean Architecture, MVVM, or Flutter Modular when creating an app.
- Choose Provider, Riverpod, Bloc, or Cubit when creating an app.
- Keep project-wide generator choices in a validated `forgekit.yaml` file.
- Adopt existing Flutter projects with automatic architecture detection.
- Preview changes, track generated files, and roll back the latest generation.
- Add profile-aware features with data, UI, routing, and dependency-injection
  wiring.
- Generate API functions from pasted JSON, including DTOs, models, payloads,
  use cases, repositories, providers, and service methods.
- Generate standalone models, screens, shared widgets, services, and use cases.
- Add Google Fonts, assets, launch icons, splash screens, and build flavors.
- Target Flutter apps and packages inside Dart pub workspaces and monorepos.
- Run `doctor` checks against the Flutter ForgeKit CLI Architecture Standard.
- Use the same CLI from the terminal or the companion VS Code extension.

## Requirements

- Dart SDK `>=3.0.0 <4.0.0`
- Flutter SDK for app generation and generated-project workflows. Newly
  generated apps require the Dart SDK bundled with current Flutter releases
  (`>=3.8.0`).
- `~/.pub-cache/bin` on your `PATH` when using globally activated Dart tools

## Installation

Copy and run:

```sh
dart pub global activate --source git https://github.com/Emmanueloluwadamilola/forgekit_cli.git
forgekit setup
```

Verify the executable:

```sh
forgekit --version
forgekit --help
```

## Mason Bricks

Flutter ForgeKit CLI shells out to Mason for app, feature, widget, and service
generation.
The `forgekit setup` command installs Mason when needed and registers the
included bricks globally so they can be used from any Flutter project. When
Flutter ForgeKit CLI is installed from GitHub, setup copies the bundled bricks
to `~/.forgekit/bricks` before registering them, so Mason can compile brick
hooks outside Dart's package cache.

You usually do not need to run `mason add` yourself. Use the manual commands
below only when you are developing Flutter ForgeKit CLI from this repository,
testing a brick directly with Mason, or debugging `forgekit setup`.

```sh
mason add -g forge_app --path bricks/forge_app
mason add -g forge_app_mvvm --path bricks/forge_app_mvvm
mason add -g forge_app_modular --path bricks/forge_app_modular
mason add -g forge_feature --path bricks/forge_feature
mason add -g forge_feature_mvvm --path bricks/forge_feature_mvvm
mason add -g forge_feature_modular --path bricks/forge_feature_modular
mason add -g forge_widget --path bricks/forge_widget
mason add -g forge_service --path bricks/forge_service
```

For local-only use, this package also includes `mason.yaml`:

```sh
mason get
```

## Quick Start

```sh
# Create a new Flutter app.
forgekit create app my_app --org com.example --font Poppins

cd my_app
flutter pub get

# Add a feature skeleton.
forgekit add feature orders

# Add an API operation to the feature.
forgekit add function orders fetch_orders --method GET --path /orders

# Add supporting UI and assets.
forgekit add screen orders order_detail
forgekit add widget primary_button
forgekit add asset ./assets/logo.png

# Check architecture conformance.
forgekit doctor
```

## Commands

```text
forgekit --version
forgekit --help
forgekit help <command>
```

| Command | Purpose |
| --- | --- |
| `forgekit setup` | Install Mason when needed and register Flutter ForgeKit CLI's bundled bricks. |
| `forgekit workspace list` | List Dart and Flutter packages in the current pub workspace. |
| `forgekit create app <name>` | Create a new Flutter ForgeKit CLI project. |
| `forgekit init` | Detect and adopt an existing Flutter project by creating `forgekit.yaml`. |
| `forgekit config show` | Print the resolved project configuration. |
| `forgekit config set <key> <value>` | Update one validated configuration value. |
| `forgekit config validate` | Validate `forgekit.yaml`. |
| `forgekit diff` | Check whether files from the latest generation have changed. |
| `forgekit rollback` | Safely undo the latest Flutter ForgeKit CLI generation transaction. |
| `forgekit add feature <name>` | Add a feature matching the configured architecture profile. |
| `forgekit add function [feature] <name>` | Generate an API operation from JSON and wire it into a feature. |
| `forgekit add model [feature] <name>` | Generate a domain model and DTO from JSON. |
| `forgekit add screen [feature] <name>` | Add a screen with a route id. |
| `forgekit add widget <name>` | Add a synced shared widget or generate a starter widget. |
| `forgekit add service <name>` | Generate a cross-cutting service. |
| `forgekit add usecase <feature> <name>` | Generate one use case in an existing feature. |
| `forgekit add font <name>` | Download and register a Google Font. |
| `forgekit add asset <file-or-folder>` | Register assets and generate typed `Drawables` constants. |
| `forgekit add flavor <a,b,c>` | Create flavor config and flavor entrypoints. |
| `forgekit add env <a,b,c>` | Create JSON-backed environment config files. |
| `forgekit set env <key> <value>` | Set an environment config value. |
| `forgekit add i18n <a,b,c>` | Scaffold Flutter localization with ARB files. |
| `forgekit add string <key> <value>` | Add a localized string to ARB files. |
| `forgekit add test <type> ...` | Generate starter tests for existing features, models, or functions. |
| `forgekit sync widget <name>` | Save an edited shared widget for reuse in other apps. |
| `forgekit registry connect <git-url>` | Connect a team-shared Git widget registry. |
| `forgekit registry pull` | Pull the connected shared registry. |
| `forgekit registry push` | Commit and push registry changes. |
| `forgekit rename feature <old> <new>` | Rename a generated feature and its identifiers. |
| `forgekit remove feature <name>` | Remove a generated feature and its tests. |
| `forgekit set icon <image>` | Configure app launcher icons. |
| `forgekit set splash <image>` | Configure the native splash screen. |
| `forgekit doctor` | Check the project against the architecture standard. Use `--fix` for safe repairs. |
| `forgekit update` | Update Flutter ForgeKit CLI from the GitHub repository and rerun setup. |

### Use Flutter ForgeKit CLI in a Workspace

Flutter ForgeKit CLI supports Dart pub workspaces, including nested workspaces and glob
entries supported by the installed Dart SDK. Inspect the packages from anywhere
inside the repository:

```sh
forgekit workspace list
forgekit workspace list --json
```

Target a Flutter package by its pubspec name or its path relative to the
workspace root:

```sh
forgekit add feature orders --package mobile_app
forgekit add screen orders order_detail --package apps/mobile_app
forgekit doctor --package mobile_app --ci
```

The global `--package` option can appear before or after the command. Flutter ForgeKit CLI
uses Dart's workspace resolver to validate the target, runs the command from
that package's directory, and does not change your shell's current directory.
The selected package must be a declared Flutter workspace package. When you are
already inside a package, commands continue to work without `--package`.

Pub workspaces require Dart 3.6 or later; workspace globs require Dart 3.11 or
later. See the [Dart pub workspace documentation](https://dart.dev/tools/pub/workspaces)
for the required `workspace:` and `resolution: workspace` configuration.

### Create an App

```sh
forgekit create app my_app
forgekit create app my_app --org com.example
forgekit create app my_app --org com.example --font Poppins
forgekit create app my_app --architecture clean
forgekit create app my_app --architecture mvvm
forgekit create app my_app --architecture modular
forgekit create app my_app --router go_router
forgekit create app my_app --state-management provider
forgekit create app my_app --state-management riverpod
forgekit create app my_app --state-management bloc
forgekit create app my_app --state-management cubit
```

`create app` runs `flutter create`, then applies the brick for the selected
architecture. When `--architecture` is omitted, Flutter ForgeKit CLI shows
`clean`, `mvvm`, and `modular` in the terminal and waits for a selection.

| Profile | Generated structure | Routing and dependency injection |
| --- | --- | --- |
| `clean` | Feature-first data, domain, and presentation layers | Named routes or GoRouter; GetIt and Injectable |
| `mvvm` | UI Views and ViewModels over shared repositories and services | Named routes or GoRouter; GetIt and Injectable |
| `modular` | Self-contained modules with data and presentation boundaries | Flutter Modular v7 owns routes and module-scoped dependencies |

MVVM follows Flutter's recommended separation between UI and data layers, with
Views paired with ViewModels and repositories acting as the source of truth.
The Modular profile uses top-level `final` modules, feature mount paths, and
module-owned dependency registration. `forgekit add feature <name>` reads
`forgekit.yaml` and automatically generates the matching feature shape. For a
Modular project, it also mounts the new module in `lib/app/app_module.dart`.

Design references: [Flutter architecture guide](https://docs.flutter.dev/app-architecture/guide),
[Flutter architecture case study](https://docs.flutter.dev/app-architecture/case-study),
and [Flutter Modular modules and composition](https://modular.flutterando.com.br/docs/flutter_modular/module/).

The default non-Modular router mode is `named`. Use `--router go_router` with
the Clean or MVVM profile. Do not pass `--router` with `--architecture modular`
because Flutter Modular owns routing.

Provider uses Flutter ForgeKit CLI's `CustomProvider` and state base classes on
top of the Provider package. The selected Provider, Riverpod, Bloc, or Cubit
stack is applied to app theme state, generated features, starter tests, and
architecture checks.

When `--state-management` is omitted, Flutter ForgeKit CLI shows Provider,
Riverpod, Bloc, and Cubit in the terminal and waits for a selection.

Every new app receives a `forgekit.yaml`, so later feature generation uses the
same router and state-management choices automatically.

### Adopt an Existing App

Run `init` from an existing Flutter project:

```sh
forgekit init
forgekit config validate
forgekit doctor
```

Flutter ForgeKit CLI inspects `pubspec.yaml` and `lib/` to detect Clean
Architecture, MVVM, Flutter Modular, Riverpod, Bloc or Cubit, routing,
dependency injection, model generation, and the API client. Detection does not
rewrite application code. Review the newly created `forgekit.yaml`, then use
normal generators.

Override ambiguous detection explicitly:

```sh
forgekit init --profile clean --state-management bloc
forgekit init --profile mvvm --state-management provider
forgekit init --profile modular --state-management riverpod
forgekit init --force
```

### Project Configuration

`forgekit.yaml` is the project-level source of truth for generator defaults
and detected architecture metadata:

```yaml
version: 1

architecture: clean
state_management: provider
router: go_router
dependency_injection: injectable
models: json_serializable
api_client: retrofit

testing:
  coverage: 80

generation:
  format: true
  build_runner: true
```

Inspect or update it without editing YAML manually:

```sh
forgekit config show
forgekit config set state-management cubit
forgekit config set generation.build-runner false
forgekit config validate
```

Command-line options take precedence where an override is supported. For
example, `forgekit add feature orders --router named` overrides the configured
router for that feature, while `--no-build-runner` overrides the generation
default for that command. State management remains project-wide; change it in
`forgekit.yaml` before generating features.

### Safe Generation

Preview a project-changing command without keeping its writes:

```sh
forgekit add feature orders --dry-run
forgekit doctor --fix --dry-run
forgekit config set router go_router --dry-run
```

Flutter ForgeKit CLI snapshots project files before supported mutating commands. A dry run
executes the same generator, prints created, modified, and deleted paths, then
restores the original files. Failed commands are restored automatically.

Successful generations record hashes and rollback backups under `.forgekit/`.
Flutter ForgeKit CLI adds this local backup directory to the target project's `.gitignore`:

```sh
forgekit diff
forgekit rollback
```

`diff` reports files edited since the latest generation. `rollback` refuses to
overwrite those later edits; after reviewing them, `forgekit rollback --force`
can explicitly restore the recorded state.

### Add a Feature

```sh
forgekit add feature orders
forgekit add feature orders --with-tests
forgekit add feature orders --router go_router
forgekit add feature orders --no-build-runner
```

The default router mode is `named`. Use `--router go_router` when the project
was created with GoRouter.

### Add a Function from JSON

```sh
forgekit add function orders fetch_orders --method GET --path /orders
```

The command prompts for response JSON and optional request payload JSON. Press
Enter on an empty line to finish each JSON block.

Generate a starter use-case test at the same time:

```sh
forgekit add function orders fetch_orders --method GET --path /orders --with-tests
```

### Add Tests

Generate tests for existing code:

```sh
forgekit add test feature orders
forgekit add test model orders order
forgekit add test function orders fetch_orders
```

Feature tests include real state/provider assertions. Model and function tests
create starter files because constructors and repository fakes depend on the
domain shape you define.

### Rename or Remove a Feature

```sh
forgekit rename feature orders purchases
forgekit remove feature purchases
forgekit remove feature purchases --force
```

`rename feature` updates the feature folder, generated file names, class names,
imports, and matching generated tests. `remove feature` deletes the feature and
matching generated tests; review route registrations after removal.

### Sync a Shared Widget

Create a starter widget:

```sh
forgekit add widget app_text_field
```

After editing the generated file, sync it into your local Flutter ForgeKit CLI widget
library:

```sh
forgekit sync widget app_text_field
```

Add the synced version to another Flutter app:

```sh
forgekit add widget app_text_field
```

Synced widgets are stored in `~/.forgekit/widgets`. When a synced widget is
added to another app, Flutter ForgeKit CLI rewrites package imports from the source project
name to the target project name.

Connect a team-shared widget registry:

```sh
forgekit registry connect https://github.com/your-org/forgekit_registry.git
forgekit registry pull
```

Push an edited widget to the shared registry:

```sh
forgekit sync widget app_text_field --push
```

On another machine or app, pull the registry and add the widget by name:

```sh
forgekit registry pull
forgekit add widget app_text_field
```

Useful options:

```sh
forgekit add widget app_text_field --force
forgekit add widget app_text_field --starter
forgekit sync widget app_text_field --path ./lib/core/presentation/widgets/app_text_field.dart
forgekit registry status
```

### Add a Model from JSON

```sh
forgekit add model money
forgekit add model orders address
```

With one argument, Flutter ForgeKit CLI writes a core model unless it can infer the feature
from the current directory. With two arguments, the first is the feature name.

### Add Assets

```sh
forgekit add asset ./logo.png
forgekit add asset ./icons --dir images --recursive
```

Flutter ForgeKit CLI registers the asset path in `pubspec.yaml` and updates
`lib/core/presentation/resources/drawables.dart`.

### Add Localization

```sh
forgekit add i18n en,fr,es
forgekit add string welcomeMessage "Welcome home"
forgekit add string welcomeMessage "Bienvenue" --locale fr
```

Flutter ForgeKit CLI creates `l10n.yaml`, ARB files in `lib/l10n/`, enables Flutter's
localization generator in `pubspec.yaml`, and adds `flutter_localizations` plus
`intl`. Run `flutter gen-l10n` after changing translations.

### Add Environment Config

```sh
forgekit add env dev,staging,prod
forgekit set env API_BASE_URL https://dev.example.com --environment dev
forgekit set env FEATURE_FLAG true --all
```

Flutter ForgeKit CLI writes JSON files under `assets/env/`, registers the folder in
`pubspec.yaml`, and creates `lib/core/config/env_config.dart`. Load the active
environment before `runApp`:

```dart
await EnvConfig.load('dev');
```

## Updating Flutter ForgeKit CLI

Refresh the GitHub-installed CLI:

```sh
forgekit update
```

This runs the GitHub activation command and then refreshes Flutter ForgeKit CLI's local
Mason brick setup.

## Architecture Checks

```sh
forgekit doctor
forgekit doctor --ci
forgekit doctor --fix
```

`doctor --fix` creates missing standard folders and files when Flutter ForgeKit
CLI can do so without overwriting existing code.

## How It Works

```text
Terminal or VS Code
        |
        v
Flutter ForgeKit CLI
        |
        +-- Mason bricks: app, feature, widget, service
        |
        +-- Native generators: function, model, screen, asset, font,
            flavor, env, i18n, icon, splash, doctor, sync, test,
            rename, remove
```

Brick-backed commands create known file structures. Native generators edit
existing files, parse JSON, update YAML, run build tools, and perform checks.

## Project Layout

```text
forgekit_cli/
|-- bin/forgekit.dart
|-- lib/
|   |-- forgekit.dart
|   `-- src/
|-- bricks/
|   |-- forge_app/
|   |-- forge_feature/
|   |-- forge_service/
|   `-- forge_widget/
|-- docs/
|   `-- ARCHITECTURE_STANDARD.md
|-- mason.yaml
`-- pubspec.yaml
```

## Development

Install dependencies:

```sh
dart pub get
```

Activate the CLI from this local checkout:

```sh
dart pub global activate --source path .
forgekit setup
```

Run the CLI from source:

```sh
dart run bin/forgekit.dart --help
```

Format and analyze package source:

```sh
dart format bin lib
dart analyze
dart test
```

Do not run `dart format .` on the whole repository. Mason templates contain
`{{mustache}}` placeholders and are not valid Dart until generated.

## Testing Bricks

Run a brick directly with Mason:

```sh
mason make forge_feature --name orders --projectName my_app --useRouter true --runBuildRunner false
```

Run generated Flutter projects with normal Flutter tooling:

```sh
flutter pub get
dart run build_runner build
flutter analyze
flutter test
```

## Security Notes

- Flutter ForgeKit CLI runs with the permissions of the current terminal process.
- Only run it against projects and input files you trust.
- JSON pasted into generator prompts is parsed locally and written into generated
  Dart files.
- Asset and native setup commands copy files into the target project.
- Font downloads request CSS and font files from Google Fonts.

## Troubleshooting

| Problem | Fix |
| --- | --- |
| `forgekit: command not found` | Add `~/.pub-cache/bin` to `PATH`, then reactivate with `dart pub global activate --source git https://github.com/Emmanueloluwadamilola/forgekit_cli.git`. |
| `Mason not found` | Run `forgekit setup`. |
| Mason cannot find a brick | Run `forgekit setup` to register the bundled bricks. |
| Generated code is missing `.g.dart` files | Run `dart run build_runner build`. |
| Feature inference fails | Pass the feature name explicitly, for example `forgekit add screen orders detail`. |
| Font lookup fails | Check the exact font name on Google Fonts and quote multi-word names. |

## Related

- [Flutter ForgeKit CLI Architecture Standard](docs/ARCHITECTURE_STANDARD.md)
- Flutter ForgeKit CLI VS Code Extension: companion repository for editor integration.
