# Flutter ForgeKit CLI

[![Generated app quality](https://github.com/Emmanueloluwadamilola/forgekit_cli/actions/workflows/generated-app-quality.yml/badge.svg)](https://github.com/Emmanueloluwadamilola/forgekit_cli/actions/workflows/generated-app-quality.yml)
[![License: Apache-2.0](https://img.shields.io/badge/License-Apache--2.0-blue.svg)](LICENSE)

ForgeKit is a local-first code-generation toolkit for Flutter teams. Its goal
is to turn a chosen Flutter architecture into repeatable CLI commands instead
of having developers manually create folders, boilerplate, routes,
repositories, DTOs, dependency-injection bindings, assets, and platform
configuration.

The product name is **Flutter ForgeKit CLI**. The executable and every terminal
command use the shorter name `forgekit`.

ForgeKit combines two kinds of generation:

- **Mason bricks** create predictable app, feature, widget, and service
  structures.
- **Native Dart generators** understand JSON, OpenAPI, YAML, existing Dart
  source, project configuration, assets, and generation history.

The result is more than a collection of templates. ForgeKit remembers the
architecture selected for a project, generates new code in the corresponding
shape, formats generated Dart, can run `build_runner`, and wraps supported
project mutations in a recorded transaction that can be inspected or rolled
back.

ForgeKit does not require an account, API key, or hosted ForgeKit service. It
runs with the filesystem and network permissions of the current terminal. A
few commands intentionally use the network or other local tools—for example,
downloading a Google Font, fetching an OpenAPI URL, running Flutter, running
Mason, or pushing a shared widget registry with Git.

## Table of contents

- [Project status and support boundary](#project-status-and-support-boundary)
- [What ForgeKit generates](#what-forgekit-generates)
- [Requirements](#requirements)
- [Installation](#installation)
- [Your first ForgeKit project](#your-first-forgekit-project)
- [How a command is executed](#how-a-command-is-executed)
- [Architecture profiles](#architecture-profiles)
- [Project configuration](#project-configuration)
- [Complete command reference](#complete-command-reference)
- [Generated project structures](#generated-project-structures)
- [Generation safety and rollback](#generation-safety-and-rollback)
- [Using ForgeKit in a monorepo](#using-forgekit-in-a-monorepo)
- [Development](#development)
- [Contributing](#contributing)
- [Security notes](#security-notes)
- [Troubleshooting](#troubleshooting)
- [License](#license)

## Project status and support boundary

Flutter ForgeKit CLI `0.1.0` is a **Git-distributed public beta**. It is useful
for reviewed team workflows and its representative generated-app smoke suite
exercises Clean, MVVM, and Modular projects across the supported routing,
state-management, storage, and OpenAPI choices. It is not yet a hands-off
production platform or a stable API. The package intentionally uses
`publish_to: none` and is installed from Git or a local checkout.

Current boundaries that matter in professional use:

- OpenAPI import currently targets the Clean Architecture profile only.
- Flavor generation is Dart-side scaffolding; native Android product flavors,
  iOS schemes, signing, and store configuration remain application-owned.
- The coverage gate fails closed: every eligible `lib/**/*.dart` file must
  appear in Flutter's LCOV report, then the reported executable lines must meet
  the configured threshold. See [`forgekit test`](#forgekit-test).
- The source is distributed under the [Apache License 2.0](LICENSE), including
  an explicit patent grant and the usual warranty disclaimer.

For team use, run ForgeKit on a clean Git branch, use explicit options in CI,
review generated diffs, and keep normal application tests, analysis, security
review, and platform release checks in place.

## What ForgeKit generates

ForgeKit can:

- Create a complete Flutter application using Clean Architecture, MVVM, or
  Flutter Modular.
- Use Provider, Riverpod, Bloc, or Cubit as the project-wide state-management
  style.
- Use named routes or GoRouter in Clean and MVVM projects; Flutter Modular owns
  routing in Modular projects.
- Add architecture-aware feature skeletons.
- Generate a complete API operation from pasted response and request JSON.
- Import an OpenAPI 3.0 or 3.1 JSON/YAML document and generate typed API
  features.
- Generate standalone domain models and JSON-serializable DTOs.
- Generate screens, shared widgets, initialized singleton services, and use
  cases, with architecture-aware route and dependency wiring.
- Generate ready-to-use SharedPreferences and encrypted secure-storage
  services, including dependencies, typed functions, DI, and startup wiring.
- Generate starter tests for features, models, and API functions.
- Copy and register assets and create typed `Drawables` constants.
- Download and register Google Fonts.
- Scaffold localization, environment configuration, and Dart-side flavors.
- Configure launcher icons and native splash screens.
- Detect and adopt existing Flutter applications.
- Rename or remove generated features.
- Store reusable widgets locally or in a shared Git registry.
- Target Flutter packages inside Dart pub workspaces.
- Check architecture conformance with `doctor`.
- Preview changes with `--dry-run`, inspect drift with `diff`, and undo the
  latest generation with `rollback`.

The architecture contract used by the generators is documented in the
[Flutter ForgeKit CLI Architecture Standard](doc/ARCHITECTURE_STANDARD.md).

## Requirements

- Dart SDK `>=3.5.4 <4.0.0` for the CLI and its pinned Mason toolchain.
- Flutter SDK for application creation and generated Flutter workflows.
- A current Flutter-bundled Dart SDK (`>=3.8.0`) for newly generated apps. The
  CLI itself installs on an older SDK than the projects it generates, so
  `forgekit create app` checks the installed Flutter toolchain first and refuses
  rather than producing a project that cannot resolve its dependencies.
  `forgekit doctor` reports the same mismatch as a warning.
- `~/.pub-cache/bin` on `PATH` when using globally activated Dart tools.
- Git for shared widget registries and CLI updates.
- Internet access only for commands that download something, such as Google
  Fonts, remote OpenAPI documents, CLI updates, or Git registries.

Verify the local toolchain:

```sh
dart --version
flutter --version
git --version
```

## Installation

### One line

```sh
dart pub global activate --source git https://github.com/Emmanueloluwadamilola/forgekit_cli.git --git-ref v0.1.0 && dart pub global run forgekit:forgekit setup
```

That installs the CLI and runs the required `setup` step in one go. It calls
setup through `dart pub global run` rather than the bare `forgekit` name, so it
works even on a shell where `~/.pub-cache/bin` is not yet on `PATH` — the most
common reason a fresh install appears to succeed and then cannot find the
command.

Add `~/.pub-cache/bin` to your `PATH` afterwards to use `forgekit` directly:

```sh
export PATH="$HOME/.pub-cache/bin:$PATH"   # add to ~/.zshrc or ~/.bashrc
forgekit --version
```

### Install from GitHub, step by step

```sh
# Pinned to the reviewed v0.1.0 release tag
FORGEKIT_REF=v0.1.0
dart pub global activate --source git \
  https://github.com/Emmanueloluwadamilola/forgekit_cli.git \
  --git-ref "$FORGEKIT_REF"
forgekit setup
```

`FORGEKIT_REF` is pinned above to the `v0.1.0` release tag. This uses Dart Pub's
`--git-ref` support to install that reviewed revision instead of following a
mutable branch. For maximum immutability, teams can instead pin the full 40-
character commit SHA that `v0.1.0` points to and record it in build and
onboarding documentation. See
[Dart's Git activation documentation](https://dart.dev/tools/pub/cmd/pub-global#activating-a-package-with-git).

`forgekit setup` ensures the tested Mason CLI version (`0.1.3`) is active,
replaces the local copies of ForgeKit's bundled bricks, and registers those
brick names in Mason's global registry. Existing global registrations with the
same `forge_*` names are replaced.

Setup writes to four locations: the global Dart executable, Mason's global brick
registry, `~/.forgekit` (or `%APPDATA%\ForgeKit`), and — if Mason was absent —
the Mason CLI itself.

To back all of that out:

```sh
forgekit uninstall --dry-run   # see exactly what would go
forgekit uninstall
```

See [Removing Flutter ForgeKit CLI](doc/UNINSTALL.md) for the options and the
manual equivalent. Removing the CLI does not affect projects it generated: they
are plain Flutter code with ordinary pub dependencies and nothing that calls
back into ForgeKit.

Expected result, abbreviated:

```text
Registered forge_app
Registered forge_app_mvvm
Registered forge_app_modular
Registered forge_feature
Registered forge_feature_mvvm
Registered forge_feature_modular
Registered forge_widget
Registered forge_service

Flutter ForgeKit CLI is ready.
Try: forgekit create app my_app
```

Verify the installation:

```sh
forgekit --version
forgekit --help
```

Expected version output:

```text
Flutter ForgeKit CLI 0.1.0 (forgekit)
```

If the shell cannot find `forgekit`, add the Dart global executable directory
to your shell configuration:

```sh
export PATH="$PATH:$HOME/.pub-cache/bin"
```

### Install from a local checkout

From this repository:

```sh
dart pub get
dart pub global activate --source path .
forgekit setup
```

Use this form while developing the CLI locally. Re-run the activation command
after changing code that must be picked up by the globally installed
executable.

## Your first ForgeKit project

The following walkthrough creates a Clean Architecture application, adds an
orders feature, generates one API function, adds UI and an asset, and checks
the final architecture.

### 1. Create the application

```sh
forgekit create app shop_app \
  --org com.example \
  --architecture clean \
  --state-management provider \
  --router named \
  --platforms android,ios
```

ForgeKit runs `flutter create` with Android and iOS enabled, applies the Clean
app brick, removes Flutter's sample widget test, and writes `forgekit.yaml`.
Omit `--platforms` when you want an interactive platform selector.

Expected final output, abbreviated:

```text
Created app "shop_app" in ./shop_app

Next steps:
  cd shop_app
  flutter pub get
  dart run build_runner build
```

The new project begins with a structure similar to:

```text
shop_app/
├── android/
├── ios/
├── lib/
│   ├── core/
│   │   ├── di/
│   │   ├── domain/
│   │   └── presentation/
│   └── main.dart
├── test/
├── forgekit.yaml
└── pubspec.yaml
```

### 2. Enter the project and prepare generated dependencies

```sh
cd shop_app
flutter pub get
dart run build_runner build
```

### 3. Add an orders feature

```sh
forgekit add feature orders --with-tests
```

Expected result:

```text
Added feature "orders".
Added 2 test file(s).
Running build_runner
build_runner finished.
```

The feature structure is approximately:

```text
lib/features/orders/
├── data/
│   ├── remote/service/orders_api_service.dart
│   └── repository/orders_repository_impl.dart
├── domain/
│   └── repository/orders_repository.dart
├── presentation/
│   ├── manager/
│   │   ├── orders_provider.dart
│   │   └── orders_state.dart
│   └── screens/orders_screen.dart
└── di/orders_module.dart
```

ForgeKit also registers the feature's primary screen in the application router.
For this named-route project it adds the screen import and route entry to
`lib/core/presentation/app/app.dart`. With GoRouter it imports and spreads the
feature route list. Re-running the command cannot duplicate a ForgeKit-owned
registration.

### 4. Generate an API function from JSON

```sh
forgekit add function orders fetch_orders \
  --method GET \
  --path /orders \
  --with-tests
```

ForgeKit asks for response JSON. Paste, for example:

```json
{
  "items": [
    {
      "id": 10,
      "reference": "ORD-001",
      "total": 125.5,
      "paid": true
    }
  ],
  "page": 1
}
```

Press Enter on a blank line to end the response block. For a GET request with
no body, press Enter again on a blank line when asked for request payload JSON.

Expected generated additions:

```text
lib/features/orders/
├── data/
│   └── remote/dto/fetch_orders_response_dto.dart
├── domain/
│   ├── entity/model/fetch_orders_response.dart
│   └── usecase/fetch_orders_usecase.dart
└── ...existing service, repository, implementation, and provider updated

test/features/orders/
└── domain/usecase/fetch_orders_usecase_test.dart
```

Representative generated domain code:

```dart
class FetchOrdersResponse {
  final List<FetchOrdersResponseItem> items;
  final int page;

  const FetchOrdersResponse({
    required this.items,
    required this.page,
  });
}

class FetchOrdersResponseItem {
  final int id;
  final String reference;
  final double total;
  final bool paid;

  const FetchOrdersResponseItem({
    required this.id,
    required this.reference,
    required this.total,
    required this.paid,
  });
}
```

The exact nullability and class names depend on the provided JSON or schema.

### 5. Add a detail screen

```sh
forgekit add screen orders order_detail
```

Expected result:

```text
Added and registered screen "OrderDetailScreen".
Created lib/features/orders/presentation/screens/order_detail_screen.dart
Registered route: /orders/order_detail
```

Generated code:

```dart
class OrderDetailScreen extends StatelessWidget {
  const OrderDetailScreen({super.key});

  static const id = '/orders/order_detail';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Order Detail')),
      body: const Center(child: Text('Order Detail')),
    );
  }
}
```

ForgeKit also updates the central named-route map:

```dart
routes: {
  '/': (_) => const HomeScreen(),
  OrderDetailScreen.id: (_) => const OrderDetailScreen(),
  // forgekit:named-routes
},
```

The equivalent GoRouter project receives a `GoRoute` automatically. A Modular
project receives a child route in the feature module.

### 6. Add an asset

```sh
forgekit add asset ../brand/logo.png
```

Expected project changes:

```text
assets/images/logo.png
pubspec.yaml
lib/core/presentation/resources/drawables.dart
```

Representative constant:

```dart
class Drawables {
  Drawables._();

  static const logo = 'assets/images/logo.png';
}
```

Use it in Flutter code:

```dart
Image.asset(Drawables.logo)
```

### 7. Check the architecture

```sh
forgekit doctor
```

Expected success output:

```text
Flutter ForgeKit CLI doctor: checking "shop_app"

All checks passed — project conforms to the standard.
```

## How a command is executed

When a project-changing command runs, ForgeKit generally performs the following
steps:

```text
Command arguments
      │
      ▼
Parse global options and subcommands
      │
      ├── resolve --package when inside a Dart workspace
      │
      ├── find the target pubspec.yaml
      │
      ├── read forgekit.yaml
      │
      ├── snapshot the project for restoration/rollback
      │
      ▼
Run a Mason brick or native Dart generator
      │
      ├── create files
      ├── update Dart source
      ├── update pubspec.yaml or other configuration
      └── optionally run supporting tools
      │
      ▼
Format changed Dart files
      │
      ├── success: record hashes and backups under .forgekit/
      ├── failure: restore the original snapshot
      └── --dry-run: print changes and restore the snapshot
```

Mason-backed commands create known structures. Native generators are used when
ForgeKit must parse input or edit existing files—for example, JSON models,
OpenAPI, environment files, localization, assets, doctor checks, and
transactions.

## Architecture profiles

The selected architecture is project-wide and is stored in `forgekit.yaml`.

### Clean Architecture

Create it with:

```sh
forgekit create app shop_app --architecture clean
```

Clean Architecture is feature-first. Each feature separates data access,
domain rules, UI state, and dependency registration.

```text
lib/features/orders/
├── data/
│   ├── remote/
│   │   ├── dto/
│   │   └── service/
│   └── repository/
├── domain/
│   ├── entity/
│   ├── repository/
│   └── usecase/
├── presentation/
│   ├── manager/
│   ├── screens/
│   └── widgets/
└── di/
```

The intended request flow is:

```text
Screen
  → Provider / Notifier / Bloc / Cubit
  → UseCase
  → Repository contract
  → Repository implementation
  → Retrofit API service
  → DTO
  → Domain model
```

Clean Architecture currently has the broadest generator support. Complete
OpenAPI feature import targets this profile.

### MVVM

Create it with:

```sh
forgekit create app shop_app --architecture mvvm
```

MVVM organizes Views and ViewModels over shared data services and repositories:

```text
lib/
├── config/di/
├── data/
│   ├── repositories/
│   └── services/
├── ui/
│   ├── core/
│   └── orders/
│       ├── view_models/
│       └── widgets/
├── utils/
└── main.dart
```

Adding a feature chooses the MVVM feature brick automatically:

```sh
forgekit add feature orders
```

### Flutter Modular

Create it with:

```sh
forgekit create app shop_app --architecture modular
```

Modular features own their data, presentation, route, and scoped dependencies:

```text
lib/modules/orders/
├── data/
│   ├── orders_api_service.dart
│   └── orders_repository.dart
├── presentation/
│   ├── orders_controller.dart
│   ├── orders_page.dart
│   └── orders_state.dart
└── orders_module.dart
```

When a Modular feature is generated, ForgeKit also mounts its module in
`lib/app/app_module.dart` using the `// forgekit:modules` marker.

Do not pass `--router` with the Modular profile. Flutter Modular owns routing.

### Command support by architecture

ForgeKit refuses unsupported combinations before writing files. It never
creates Clean Architecture directories inside an MVVM or Modular project as a
fallback. Lean and Legacy projects are adoption-only and reject
architecture-specific generators.

| Command family | Clean | MVVM | Modular |
| --- | --- | --- | --- |
| App, feature, screen, generic service, storage service | Supported | Supported | Supported |
| Asset constants, fonts, environment config, flavors | Supported | Supported | Supported |
| Synced widget installation | Supported | Supported | Supported |
| Starter widget brick | Supported | Explicitly rejected | Explicitly rejected |
| JSON `add model` and `add function` | Supported | Explicitly rejected | Explicitly rejected |
| `add usecase`, model/function tests | Supported | Explicitly rejected | Explicitly rejected |
| OpenAPI complete-feature import | Supported | Explicitly rejected | Explicitly rejected |
| Feature rename and removal | Supported | Explicitly rejected | Explicitly rejected |

The explicit rejections are part of the `0.1.0` compatibility contract. They
will be replaced with profile-native generators only when the resulting code
can preserve each architecture's boundaries and pass generated-app tests.

### State management

Choose one project-wide style:

```sh
--state-management provider
--state-management riverpod
--state-management bloc
--state-management cubit
```

The choice affects app theme state, feature state classes, manager classes,
generated starter tests, and doctor checks.

When the option is omitted during app creation, ForgeKit displays an
interactive choice. Provider is the default.

## Project configuration

Every new ForgeKit app contains a `forgekit.yaml` file:

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

The settings currently used directly by generators are:

- `architecture`: chooses the app/feature shape.
- `state_management`: chooses Provider, Riverpod, Bloc, or Cubit templates.
- `router`: chooses named routes, GoRouter, or Modular routing behavior.
- `generation.format`: formats changed Dart files after generation.
- `generation.build_runner`: controls automatic `build_runner` execution for
  commands that support it.
- `testing.coverage`: sets the minimum coverage for eligible executable lines.
  ForgeKit also fails when an eligible `lib/**/*.dart` file is absent from
  Flutter's LCOV report.

The version 1 file is also an enforceable generator contract. ForgeKit refuses
recognized but unsupported backend values before it writes generated code. It
does not silently combine one backend's configuration with another backend's
templates.

| Architecture | `dependency_injection` | `models` | `api_client` |
| --- | --- | --- | --- |
| Clean, MVVM | `injectable` | `json_serializable` | `retrofit` |
| Flutter Modular | `flutter_modular` | `json_serializable` | `retrofit` |
| Lean, Legacy | Adoption-only; generation rejected | Adoption-only; generation rejected | Adoption-only; generation rejected |

Clean, MVVM, and Modular are the generation backends implemented in
configuration version 1. Lean and Legacy preserve detected configuration
without pretending a standard Flutter project already has ForgeKit's
architecture markers and dependency wiring.
Values such as `get_it`, `riverpod`, `freezed`, `dio`, and `http` may already
exist in an adopted application, but they are not selectable ForgeKit code
generation backends yet. This is separate from `state_management`: Riverpod is
fully supported as a state manager while Injectable or Flutter Modular still
owns dependency injection.

Inspect the resolved configuration:

```sh
forgekit config show
```

Update one value:

```sh
forgekit config set state_management cubit
forgekit config set router go_router
forgekit config set generation.format false
forgekit config set generation.build_runner false
forgekit config set testing.coverage 85
```

Hyphenated aliases are normalized, so the following is also accepted:

```sh
forgekit config set state-management cubit
```

Validate the file:

```sh
forgekit config validate
```

Expected result:

```text
forgekit.yaml is valid.
```

## Complete command reference

The command surface at a glance:

| Command | Primary result |
| --- | --- |
| `forgekit setup` | Installs Mason when needed and registers bundled bricks. |
| `forgekit workspace list` | Lists Dart and Flutter packages in a pub workspace. |
| `forgekit create app <name>` | Creates a new architecture-configured Flutter app. |
| `forgekit init` | Detects an existing app and writes `forgekit.yaml`. |
| `forgekit config show` | Prints the project generator configuration. |
| `forgekit config set <key> <value>` | Updates one validated configuration value. |
| `forgekit config validate` | Validates `forgekit.yaml`. |
| `forgekit add feature <name>` | Creates a profile-aware feature skeleton. |
| `forgekit add function ...` | Generates and wires an API operation from JSON. |
| `forgekit import openapi ...` | Generates complete Clean API features from OpenAPI 3.0/3.1. |
| `forgekit add model ...` | Generates a domain model and DTO from JSON. |
| `forgekit add screen ...` | Creates a screen with a route id. |
| `forgekit add widget <name>` | Installs a synced widget or creates a starter. |
| `forgekit add service <name>` | Creates a generic service or a fully wired storage service with `--driver`. |
| `forgekit uninstall` | Removes ForgeKit and everything `setup` installed. `--dry-run` to preview. |
| `forgekit add usecase ...` | Creates a starter Clean Architecture use case. |
| `forgekit add font <family>` | Downloads and registers a Google Font. |
| `forgekit add asset <path>` | Copies/registers assets and generates constants. |
| `forgekit add flavor <names>` | Creates Dart flavor config and entrypoints. |
| `forgekit add env <names>` | Creates JSON-backed environment configuration. |
| `forgekit set env ...` | Changes an environment value. |
| `forgekit add i18n <locales>` | Creates Flutter localization configuration and ARB files. |
| `forgekit add string ...` | Adds a localized message to ARB files. |
| `forgekit add test ...` | Creates starter feature, model, or function tests. |
| `forgekit test` | Runs Flutter tests and gates the eligible lines reported in LCOV. |
| `forgekit rename feature ...` | Renames a generated Clean feature and identifiers. |
| `forgekit remove feature ...` | Removes a generated Clean feature and tests. |
| `forgekit sync widget ...` | Saves a widget for reuse. |
| `forgekit registry ...` | Manages a Git-backed shared widget registry. |
| `forgekit set icon <image>` | Configures launcher icons. |
| `forgekit set splash <image>` | Configures the native splash screen. |
| `forgekit doctor` | Checks project conformance and optionally repairs safe gaps. |
| `forgekit diff` | Detects drift since the latest generation. |
| `forgekit rollback` | Restores the latest recorded transaction after drift checks. |
| `forgekit update --ref <commit>` | Installs a reviewed immutable CLI revision and refreshes its bricks. |

### Global help and version

```sh
forgekit --help
forgekit --version
forgekit help add
forgekit help add feature
```

`--help` lists global options and command groups. `help <command>` narrows the
output to a command or subcommand.

### Global `--dry-run`

Preview a supported project mutation without keeping it:

```sh
forgekit add feature orders --dry-run
forgekit config set router go_router --dry-run
forgekit doctor --fix --dry-run
```

Expected result, abbreviated:

```text
Planned changes (8):
  + lib/features/orders/data/remote/service/orders_api_service.dart
  + lib/features/orders/data/repository/orders_repository_impl.dart
  + lib/features/orders/domain/repository/orders_repository.dart
  ...
Dry run complete. No project files were changed.
```

The option may appear before or after the command. It is supported by `add`,
`config`, `doctor`, `import`, `init`, `remove`, `rename`, and `set`.

### `forgekit setup`

```sh
forgekit setup
```

Use this after installing or updating ForgeKit. It installs Mason when needed
at ForgeKit's tested version (`0.1.3`) and globally registers the bundled
bricks. It is safe to run repeatedly, but it deliberately replaces existing
registrations named `forge_app`, `forge_feature`, and the other bundled
`forge_*` bricks.

No Flutter project is required because this command configures the user's
ForgeKit and Mason directories.

### `forgekit workspace list`

List packages in the current Dart pub workspace:

```sh
forgekit workspace list
```

Expected result:

```text
Workspace: /work/company_app
  company_app              .                                Dart
  mobile_app               apps/mobile                      Flutter
  shared_models            packages/shared_models           Dart
```

Machine-readable output:

```sh
forgekit workspace list --json
```

Representative JSON:

```json
{
  "root": "/work/company_app",
  "packages": [
    {
      "name": "mobile_app",
      "path": "apps/mobile",
      "flutter": true
    }
  ]
}
```

### `forgekit create app`

Basic call:

```sh
forgekit create app my_app
```

The project name must be a lowercase Dart package name such as `shop_app`, not
a filesystem path. ForgeKit refuses any existing file, directory, or symbolic
link at the destination. If Flutter or Mason fails after creating the new
directory, ForgeKit removes the incomplete destination instead of leaving a
partially generated app.

Non-interactive architecture options:

```sh
forgekit create app my_app \
  --org com.example \
  --architecture clean \
  --state-management riverpod \
  --router go_router \
  --platforms android,ios,web
```

Create a web-only application without any interactive questions:

```sh
forgekit create app admin_portal \
  --org com.example \
  --architecture mvvm \
  --state-management bloc \
  --router go_router \
  --platforms web
```

Expected final output, abbreviated:

```text
Created app "admin_portal" in ./admin_portal

Next steps:
  cd admin_portal
  flutter pub get
  dart run build_runner build
```

Add a Google Font during creation:

```sh
forgekit create app my_app --font Poppins
forgekit create app my_app --font "Plus Jakarta Sans"
```

Arguments and options:

| Input | Meaning |
| --- | --- |
| `<name>` | Flutter project and Dart package name. |
| `--org` | Reverse-domain organization; default `com.forgecyberlabs`. |
| `--font` | Google Font family to download after app generation. |
| `--architecture` | `clean`, `mvvm`, or `modular`. |
| `--state-management` | `provider`, `riverpod`, `bloc`, or `cubit`. |
| `--router` | `named` or `go_router`; unavailable with `modular`. |
| `--platforms` | Comma-separated Flutter platforms: `android`, `ios`, `web`, `macos`, `windows`, and/or `linux`. |

Interactive behavior:

- If architecture is omitted, ForgeKit asks for Clean, MVVM, or Modular.
- If state management is omitted, ForgeKit asks for Provider, Riverpod, Bloc,
  or Cubit.
- In Clean and MVVM projects, if routing is omitted, ForgeKit asks for GoRouter
  or named routes. GoRouter is the default selection. Modular projects use
  Flutter Modular routing and do not show this question.
- If `--platforms` is omitted, ForgeKit asks which Flutter target platforms
  should be enabled.
- Supplying architecture, state management, router, and platforms makes app
  creation fully non-interactive, which is useful in scripts and CI.

Generated result:

```text
my_app/
├── platform folders selected by --platforms or the prompt
├── lib/                         # architecture-specific source
├── forgekit.yaml                # future generator defaults
├── pubspec.yaml                 # architecture dependencies
└── analysis_options.yaml
```

### `forgekit init`

Adopt an existing Flutter project:

```sh
cd existing_app
forgekit init
```

ForgeKit inspects `pubspec.yaml` and `lib/` to infer architecture, state
management, and routing. It then records the supported generation backend for
that architecture. Existing packages are not misrepresented as selectable
ForgeKit backends. The command writes configuration only; it does not rewrite
the application.

An application that does not match the Clean, MVVM, or Modular layouts is
recorded as `lean`. Lean and Legacy are adoption-only profiles in `0.1.0`:
configuration, inspection, and architecture-neutral workflows remain
available, while feature, screen, service, and architecture repair commands
fail explicitly instead of creating Clean folders inside the existing app.
Migrating an app to a generated architecture requires deliberate application
work; changing only `forgekit.yaml` is not a migration.

Expected result:

```text
Created /work/existing_app/forgekit.yaml.
  architecture: clean
  state management: riverpod
  router: go_router
  dependency injection: injectable
  models: json_serializable
  API client: retrofit
```

Override ambiguous detection:

```sh
forgekit init --profile clean --state-management bloc
```

Replace an existing configuration after reviewing it:

```sh
forgekit init --force
```

Preview adoption without keeping `forgekit.yaml`:

```sh
forgekit init --dry-run
```

### `forgekit config`

Show the complete resolved file:

```sh
forgekit config show
```

Set one value:

```sh
forgekit config set <key> <value>
```

Examples:

```sh
forgekit config set router named
forgekit config set state_management riverpod
forgekit config set generation.build_runner false
forgekit config set testing.coverage 90
```

Validate without changing anything:

```sh
forgekit config validate
```

### `forgekit add feature`

```sh
forgekit add feature orders
```

ForgeKit reads the architecture and state manager from `forgekit.yaml`, chooses
the matching feature brick, creates the skeleton, and normally runs
`build_runner`.

Options:

```sh
forgekit add feature orders --with-tests
forgekit add feature orders --router go_router
forgekit add feature orders --no-build-runner
```

Expected Clean/Provider result:

```text
lib/features/orders/
├── data/remote/service/orders_api_service.dart
├── data/repository/orders_repository_impl.dart
├── domain/repository/orders_repository.dart
├── presentation/manager/orders_provider.dart
├── presentation/manager/orders_state.dart
├── presentation/screens/orders_screen.dart
└── di/orders_module.dart
```

Expected manager name by state-management profile:

| Configuration | Generated manager |
| --- | --- |
| Provider | `OrdersProvider` |
| Riverpod | `OrdersNotifier` and provider declaration |
| Bloc | `OrdersBloc` |
| Cubit | `OrdersCubit` |

Route wiring is automatic:

- Named-route projects import the primary screen and add it to the central
  `MaterialApp.routes` map.
- GoRouter projects import the generated feature route list and spread it into
  the central `GoRouter` route collection.
- Modular projects mount the generated feature module in `app_module.dart`.

ForgeKit-owned insertions are tagged and idempotent. The command fails instead
of silently leaving an unwired feature when the expected application routing
location cannot be found. `--router` may be supplied for scripting, but it must
match the router recorded in `forgekit.yaml`; one application cannot safely mix
incompatible central router styles.

### `forgekit add function`

Add an API operation to an existing Clean Architecture feature:

```sh
forgekit add function orders create_order \
  --method POST \
  --path /orders
```

Supported HTTP methods are `GET`, `POST`, `PUT`, `PATCH`, and `DELETE`. If
`--method` or `--path` is omitted, ForgeKit prompts for it.

Response JSON example:

```json
{
  "id": 42,
  "reference": "ORD-042",
  "status": "pending"
}
```

Request JSON example:

```json
{
  "productId": 7,
  "quantity": 2
}
```

Expected files:

```text
lib/features/orders/
├── data/remote/dto/
│   ├── create_order_payload_dto.dart
│   └── create_order_response_dto.dart
├── domain/entity/
│   ├── model/create_order_response.dart
│   └── payload/create_order_payload.dart
└── domain/usecase/create_order_usecase.dart
```

Expected edits:

- Adds the Retrofit endpoint to `orders_api_service.dart`.
- Adds the operation to `orders_repository.dart`.
- Implements it in `orders_repository_impl.dart`.
- Adds the state-management operation to the generated manager.
- Adds any necessary imports to those files.

Representative generated flow:

```dart
// API service
@POST('/orders')
Future<CreateOrderResponseDto> createOrder(
  @Body() CreateOrderPayloadDto payload,
);

// Domain repository
Future<ApiResult<CreateOrderResponse>> createOrder(
  CreateOrderPayload payload,
);

// Use case
class CreateOrderUsecase
    extends UseCase<CreateOrderResponse, CreateOrderPayload> {
  final OrdersRepository _repository;

  CreateOrderUsecase(this._repository);

  @override
  Future<ApiResult<CreateOrderResponse>> call(
    CreateOrderPayload params,
  ) {
    return _repository.createOrder(params);
  }
}
```

The exact emitted signatures depend on method, payload, response shape, and
state-management profile.

Generate a starter use-case test at the same time:

```sh
forgekit add function orders create_order \
  --method POST \
  --path /orders \
  --with-tests
```

When already inside `lib/features/orders/`, the feature can be inferred:

```sh
forgekit add function create_order --method POST --path /orders
```

### `forgekit import openapi`

Import a local OpenAPI 3.0 or 3.1 document:

```sh
forgekit import openapi ./openapi.yaml
```

Import a remote document:

```sh
forgekit import openapi https://api.example.com/openapi.json
```

Operations are grouped by their first OpenAPI tag. Untagged operations are
grouped by the first useful URL path segment.

Given operations tagged `Products` and `Orders`, the result is approximately:

```text
lib/features/
├── products/
│   ├── data/
│   ├── domain/
│   ├── presentation/
│   └── di/
└── orders/
    ├── data/
    ├── domain/
    ├── presentation/
    └── di/
```

Each operation can generate:

- Path, query, header, and scalar cookie inputs.
- A typed request payload and DTO.
- A typed response model and DTO.
- A parameter object for the use case.
- A Retrofit endpoint.
- Repository contract and implementation methods.
- A use case.
- A Provider, Riverpod, Bloc, or Cubit operation.
- Executable DTO/model round-trip tests.

For example, a protected `PUT /users/{userId}` operation with a reusable JSON
request body and response produces code in this shape:

```text
lib/features/users/
├── data/
│   ├── remote/
│   │   ├── dto/
│   │   │   ├── update_user_payload_dto.dart
│   │   │   └── update_user_response_dto.dart
│   │   └── service/users_api_service.dart
│   └── repository/users_repository_impl.dart
├── domain/
│   ├── entity/
│   │   ├── model/update_user_response.dart
│   │   └── payload/
│   │       ├── update_user_params.dart
│   │       └── update_user_payload.dart
│   ├── repository/users_repository.dart
│   └── usecase/update_user_usecase.dart
├── presentation/
│   ├── manager/users_provider.dart
│   └── screens/users_screen.dart
└── di/users_module.dart

test/features/users/data/remote/dto/
├── update_user_payload_dto_test.dart
└── update_user_response_dto_test.dart
```

Authentication remains a runtime value. For an HTTP bearer scheme, ForgeKit
adds an `authorization` parameter rather than writing a token into source:

```dart
final result = await updateUserUsecase(
  UpdateUserParams(
    userId: 'usr_123',
    authorization: 'Bearer $accessToken',
    payload: const UpdateUserPayload(name: 'Ada'),
  ),
);
```

Header/query API keys become typed operation parameters. Scalar cookie
parameters and cookie API keys are URL-encoded and combined into the outgoing
`Cookie` header. Security alternatives and OAuth scopes are also retained on
the Retrofit method in `forgekit.security` request metadata, so an application
Dio interceptor can enforce or resolve credentials centrally. OAuth login,
token refresh, OpenID Connect discovery, and mutual-TLS certificate ownership
remain application concerns; a generator cannot safely invent those policies.

Useful options:

```sh
# Import only selected tags.
forgekit import openapi ./openapi.yaml --tag Users --tag Auth

# Put every selected operation in one feature.
forgekit import openapi ./openapi.yaml --feature accounts

# Override the first server URL in the specification.
forgekit import openapi ./openapi.yaml \
  --base-url https://staging.example.com

# Skip tests or defer build_runner.
forgekit import openapi ./openapi.yaml --no-tests --no-build-runner

# Replace an existing feature with the same generated name.
forgekit import openapi ./openapi.yaml --force

# Permit a trusted local file to fetch its declared HTTPS references.
forgekit import openapi ./openapi.yaml --allow-remote-references
```

OpenAPI support contract:

| Area | Supported behavior |
| --- | --- |
| Versions | OpenAPI 3.0.x and 3.1.x in JSON or YAML. Swagger 2 and OpenAPI 3.2 are rejected. |
| References | Internal JSON Pointer references and multi-document `$ref` values. Local references must remain below the entry file's directory. A local file requires `--allow-remote-references` before fetching HTTPS references. Remote documents and redirects must remain on the original HTTPS origin. |
| Components | Reusable schemas, parameters, request bodies, responses, and security schemes. |
| Schemas | Objects, arrays, primitives, nullable 3.0 schemas, 3.1 type arrays, `additionalProperties`, `allOf`, and practical `oneOf`/`anyOf` object unions. Object unions generate a superset model; incompatible same-name variant properties are rejected. JSON Schema `$id` base-URI changes are rejected rather than resolved incorrectly. |
| Operations | GET, POST, PUT, PATCH, DELETE, HEAD, and OPTIONS; default-style path, query, header, and scalar cookie parameters; required and optional JSON bodies; first exact or wildcard `2XX` response, then `default`. |
| Servers | The first server URL is used and server variables are expanded from their required defaults; `--base-url` can override it. |
| JSON media | `application/json`, vendor `+json` types, and `*/*`. Unsupported request/response media types fail with a concrete error instead of being generated incorrectly. |
| Security | API keys in headers, queries, or cookies; HTTP auth; OAuth2; OpenID Connect; mutual TLS; global and operation-level alternatives; OAuth scopes preserved as Retrofit request metadata. |
| Generated validation | DTO/model JSON round-trip tests plus generated-app `build_runner`, `doctor`, `flutter analyze`, and executable test validation. Coverage-threshold behavior is tested independently by the CLI suite. |

Complete-feature emission currently targets the Clean Architecture profile.
Multipart/form-data, form-urlencoded and binary bodies, callbacks, webhooks,
links, generated OAuth flows, and certificate
provisioning are not emitted in `0.1.0`. These boundaries are explicit because
claiming every OpenAPI feature while silently dropping behavior would be unsafe
for a production generator.

Use `--dry-run` before a large import:

```sh
forgekit import openapi ./openapi.yaml --dry-run
```

### `forgekit add model`

Generate a core model:

```sh
forgekit add model money
```

Generate a feature model:

```sh
forgekit add model orders address
forgekit add model address --feature orders
```

Paste JSON when prompted:

```json
{
  "street": "1 Flutter Way",
  "city": "Lagos",
  "coordinates": {
    "latitude": 6.5244,
    "longitude": 3.3792
  }
}
```

Expected feature files:

```text
lib/features/orders/
├── domain/entity/model/address.dart
└── data/remote/dto/address_dto.dart
```

Expected core files when no feature is selected:

```text
lib/core/domain/entity/
├── model/address.dart
└── dto/address_dto.dart
```

The DTO uses `@JsonSerializable`, contains a generated-part declaration, and
maps to the plain domain model:

```dart
@JsonSerializable(explicitToJson: true)
class AddressDto {
  const AddressDto({
    required this.street,
    required this.city,
    required this.coordinates,
  });

  final String street;
  final String city;
  final AddressCoordinatesDto coordinates;

  factory AddressDto.fromJson(Map<String, dynamic> json) =>
      _$AddressDtoFromJson(json);

  Map<String, dynamic> toJson() => _$AddressDtoToJson(this);

  Address toModel() => Address(
        street: street,
        city: city,
        coordinates: coordinates.toModel(),
      );
}
```

Run `build_runner` to produce the `.g.dart` file. ForgeKit does this by default
unless disabled.

### `forgekit add screen`

```sh
forgekit add screen orders order_detail
```

From inside a Clean feature, the shorter form works:

```sh
forgekit add screen order_detail
```

Expected file:

```text
lib/features/orders/presentation/screens/order_detail_screen.dart
```

The generated `StatelessWidget` includes a static route id, an `AppBar`, and a
placeholder body. ForgeKit immediately registers it in the configured router.

Expected Clean result:

```text
Added and registered screen "OrderDetailScreen".

Created lib/features/orders/presentation/screens/order_detail_screen.dart
Registered route: /orders/order_detail
```

Generated locations and routing behavior:

| Architecture | Generated screen | Automatic registration |
| --- | --- | --- |
| Clean | `lib/features/orders/presentation/screens/order_detail_screen.dart` | Central named map or `GoRouter` list |
| MVVM | `lib/ui/orders/widgets/order_detail_screen.dart` | Central named map or `GoRouter` list |
| Modular | `lib/modules/orders/presentation/order_detail_screen.dart` | Child route in `orders_module.dart` |

For Clean and MVVM, additional screen ids are feature-qualified
(`/orders/order_detail`) to prevent route collisions between features. Modular
screens use a module-relative child path (`/order_detail`). Registrations carry
ForgeKit ownership markers, so the same route is never inserted twice.

### `forgekit add widget`

```sh
forgekit add widget primary_button
```

ForgeKit first searches for a locally synced or shared-registry widget. If it
finds one, it installs that widget. Otherwise it generates the starter brick.

Starter output:

```text
lib/core/presentation/widgets/primary_button.dart
```

Representative starter:

```dart
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    this.onTap,
  });

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelLarge,
        ),
      ),
    );
  }
}
```

Useful options:

```sh
# Ignore a synced version and use the starter template.
forgekit add widget primary_button --starter

# Overwrite an existing target when installing a synced widget.
forgekit add widget primary_button --force
```

### `forgekit add service`

#### Generic service

```sh
forgekit add service analytics
```

In an interactive terminal, omitting `--driver` opens this selection:

```text
Select service type:
  generic
  shared_preferences
  flutter_secure_storage
```

Choose `generic` for an SDK adapter or other cross-cutting service whose
implementation you will complete. For scripts and CI, make that choice
explicit:

```sh
forgekit add service analytics --driver generic
```

Expected file:

```text
lib/services/analytics_service.dart
```

Generated shape:

```dart
@lazySingleton
class AnalyticsService {
  bool _initialized = false;

  bool get isInitialized => _initialized;

  Future<void> init() async {
    if (_initialized) return;

    // Configure SDKs, permissions, subscriptions, or other resources.
    _initialized = true;
  }
}
```

ForgeKit performs the startup wiring itself. In Clean and MVVM projects it
registers the service through Injectable, runs `build_runner` according to
`forgekit.yaml`, imports the service in `main.dart`, and inserts initialization
after `configureDependencies()` but before `runApp`:

```dart
await configureDependencies();
await getIt<AnalyticsService>().init();
runApp(const App());
```

Expected output, abbreviated:

```text
Added and initialized AnalyticsService.

Generated:
  lib/services/analytics_service.dart
Updated:
  lib/main.dart
  Injectable dependency graph (via build_runner)

AnalyticsService is initialized before runApp.
```

For Modular, ForgeKit creates one top-level `analyticsService` instance,
registers that exact instance in `app_module.dart`, and awaits its `init()` in
`main.dart`. It does not add an Injectable annotation or run an irrelevant DI
builder. This guarantees that the instance initialized at startup is the same
instance later resolved by the application.

#### Local storage with SharedPreferences

```sh
forgekit add service local_storage --driver shared_preferences
```

The name should describe the service without a trailing `_service`; ForgeKit
adds that suffix to the filename and class.

This single command:

1. Adds `shared_preferences` to `pubspec.yaml` if it is missing.
2. Creates `lib/services/local_storage_service.dart`.
3. Generates complete asynchronous getters, setters, key inspection, removal,
   and clearing functions using `SharedPreferencesAsync`.
4. Registers the service with Injectable/GetIt in Clean and MVVM projects.
5. Registers the initialized instance with Flutter Modular in Modular
   projects.
6. Adds an idempotent `init()` call before `runApp`.
7. Runs `flutter pub get`.
8. Runs `build_runner` for Injectable projects unless disabled by
   `forgekit.yaml` or `--no-build-runner`.

Expected result, abbreviated:

```text
Added LocalStorageService with shared_preferences.
flutter pub get finished.
build_runner finished.

Generated:
  lib/services/local_storage_service.dart
Updated:
  pubspec.yaml
  lib/main.dart
  Injectable dependency graph (via build_runner)

LocalStorageService is initialized before runApp.
```

Generated structure:

```text
lib/
├── main.dart
└── services/
    └── local_storage_service.dart

pubspec.yaml
```

Representative generated service:

```dart
import 'package:injectable/injectable.dart';
import 'package:shared_preferences/shared_preferences.dart';

@lazySingleton
class LocalStorageService {
  final SharedPreferencesAsync _preferences = SharedPreferencesAsync();
  bool _initialized = false;

  bool get isInitialized => _initialized;

  Future<void> init() async {
    if (_initialized) return;
    await _preferences.getKeys();
    _initialized = true;
  }

  Future<String?> getString(String key) {
    _ensureInitialized();
    return _preferences.getString(key);
  }

  Future<void> setString(String key, String value) {
    _ensureInitialized();
    return _preferences.setString(key, value);
  }

  Future<void> remove(String key) {
    _ensureInitialized();
    return _preferences.remove(key);
  }

  Future<void> clear({Set<String>? allowList}) {
    _ensureInitialized();
    return _preferences.clear(allowList: allowList);
  }

  void _ensureInitialized() {
    if (!_initialized) {
      throw StateError(
        'LocalStorageService.init() must be called before use.',
      );
    }
  }
}
```

The complete generated API includes:

```dart
Future<Object?> get(String key);
Future<String?> getString(String key);
Future<bool?> getBool(String key);
Future<int?> getInt(String key);
Future<double?> getDouble(String key);
Future<List<String>?> getStringList(String key);

Future<void> setString(String key, String value);
Future<void> setBool(String key, bool value);
Future<void> setInt(String key, int value);
Future<void> setDouble(String key, double value);
Future<void> setStringList(String key, List<String> value);

Future<bool> containsKey(String key);
Future<Set<String>> getKeys();
Future<void> remove(String key);
Future<void> clear({Set<String>? allowList});
```

ForgeKit adds this initialization after dependency configuration and before
`runApp`:

```dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await configureDependencies();

  await getIt<LocalStorageService>().init();
  // forgekit:service-initializers

  runApp(const App());
}
```

Use the service through constructor injection:

```dart
@lazySingleton
class SettingsRepository {
  const SettingsRepository(this._storage);

  final LocalStorageService _storage;

  Future<bool> hasCompletedOnboarding() async {
    return await _storage.getBool('completed_onboarding') ?? false;
  }

  Future<void> completeOnboarding() {
    return _storage.setBool('completed_onboarding', true);
  }
}
```

SharedPreferences is appropriate for non-sensitive values such as theme mode,
locale, onboarding state, feature preferences, and small cached settings. Do
not use it for access tokens, secrets, critical writes, or a large application
database. The generated service uses `SharedPreferencesAsync`, so reads always
consult the platform implementation rather than relying on a process-local
cache that can become stale across isolates or Flutter engines. See the
[official shared_preferences guidance](https://pub.dev/documentation/shared_preferences/latest/).

#### Secure storage with Flutter Secure Storage

```sh
forgekit add service secure_storage \
  --driver flutter_secure_storage
```

This command performs the same dependency, DI, bootstrap, package, and code
generation workflow, but creates an encrypted storage wrapper backed by
`FlutterSecureStorage`.

ForgeKit targets the tested `flutter_secure_storage` 10.x baseline. Review its
platform setup before shipping: Android applications must use the package's
current minimum SDK and migration settings; web storage requires HTTPS or
localhost; Linux requires the documented `libsecret` development/runtime
packages; and Apple/Windows applications must satisfy their
Keychain/credential-store build requirements. Follow the
[upstream platform instructions](https://pub.dev/packages/flutter_secure_storage)
and test upgrades against existing encrypted values before release.

Expected result:

```text
Generated:
  lib/services/secure_storage_service.dart
Updated:
  pubspec.yaml
  lib/main.dart

SecureStorageService is initialized before runApp.
```

Representative generated service:

```dart
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:injectable/injectable.dart';

@lazySingleton
class SecureStorageService {
  SecureStorageService() : _storage = const FlutterSecureStorage();

  final FlutterSecureStorage _storage;
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    await _storage.readAll();
    _initialized = true;
  }

  Future<void> setString(String key, String value) {
    _ensureInitialized();
    return _storage.write(key: key, value: value);
  }

  Future<String?> getString(String key) {
    _ensureInitialized();
    return _storage.read(key: key);
  }

  Future<void> remove(String key) {
    _ensureInitialized();
    return _storage.delete(key: key);
  }

  Future<void> clear() {
    _ensureInitialized();
    return _storage.deleteAll();
  }
}
```

The complete generated secure API includes typed helpers for strings, booleans,
integers, doubles, and string lists, plus:

```dart
Future<bool> containsKey(String key);
Future<Map<String, String>> readAll();
Future<void> remove(String key);
Future<void> clear();
```

Use secure storage for access tokens, refresh tokens, session credentials,
encryption keys, or other sensitive values:

```dart
@lazySingleton
class SessionRepository {
  const SessionRepository(this._storage);

  final SecureStorageService _storage;

  Future<void> saveAccessToken(String token) {
    return _storage.setString('access_token', token);
  }

  Future<String?> getAccessToken() {
    return _storage.getString('access_token');
  }

  Future<void> signOut() {
    return _storage.clear();
  }
}
```

#### Storage drivers with Flutter Modular

Modular projects do not use Injectable/GetIt. ForgeKit generates one top-level
service instance, registers that same instance in `appModule`, and initializes
it before `runApp`:

```dart
// local_storage_service.dart
final localStorageService = LocalStorageService();
```

```dart
// app_module.dart
c
  ..addInstance<LocalStorageService>(localStorageService)
  // forgekit:services
  ..route('/', child: (_, __) => const HomePage());
```

```dart
// main.dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await localStorageService.init();
  // forgekit:service-initializers

  runApp(ModularApp(module: appModule, child: const App()));
}
```

Feature classes can receive the service through Modular constructor injection.

#### Controlling code generation

Use the project default from `forgekit.yaml`:

```yaml
generation:
  build_runner: true
```

Or override it for one storage service:

```sh
forgekit add service local_storage \
  --driver shared_preferences \
  --no-build-runner
```

When `build_runner` is skipped in a Clean or MVVM project, ForgeKit still
writes the service and bootstrap call, then reminds you to run:

```sh
dart run build_runner build
```

Both driver commands support `--dry-run`, so dependencies, generated code, and
bootstrap edits can be previewed and restored:

```sh
forgekit add service local_storage \
  --driver shared_preferences \
  --dry-run
```

### `forgekit add usecase`

```sh
forgekit add usecase orders cancel_order
```

Expected file:

```text
lib/features/orders/domain/usecase/cancel_order_usecase.dart
```

Generated starter:

```dart
class CancelOrderUsecase extends UseCase<dynamic, NoParams> {
  CancelOrderUsecase();

  @override
  Future<ApiResult<dynamic>> call(NoParams params) {
    // TODO: implement call by delegating to a repository.
    throw UnimplementedError();
  }
}
```

Replace the placeholder types and delegate to the appropriate repository.

### `forgekit add font`

```sh
forgekit add font Poppins
forgekit add font "Plus Jakarta Sans"
```

ForgeKit requests the Google Fonts stylesheet, downloads available static TTF
weights, stores them under `assets/fonts/`, registers the family in
`pubspec.yaml`, and tries to add the family to the app theme.

Expected structure:

```text
assets/fonts/Poppins/
├── Poppins-Regular.ttf
├── Poppins-Medium.ttf
├── Poppins-SemiBold.ttf
└── Poppins-Bold.ttf
```

Representative `pubspec.yaml` section:

```yaml
flutter:
  fonts:
    - family: Poppins
      fonts:
        - asset: assets/fonts/Poppins/Poppins-Regular.ttf
          weight: 400
        - asset: assets/fonts/Poppins/Poppins-Bold.ttf
          weight: 700
```

Available files depend on what Google Fonts exposes for the family. If the
project theme cannot be identified safely, ForgeKit prints the manual
`ThemeData(fontFamily: ...)` step instead of failing the entire command.

### `forgekit add asset`

Add one file:

```sh
forgekit add asset ../design/logo.png
```

Default destination by extension:

- Images and SVG files → `assets/images/`
- Lottie/JSON animation files → `assets/lottie/`
- Other files → `assets/files/`

Select a specific subdirectory:

```sh
forgekit add asset ../design/logo.png --dir branding
```

Add a folder:

```sh
forgekit add asset ../design/icons
forgekit add asset ../design/icons --recursive
```

Expected changes:

```text
assets/<selected-directory>/...
pubspec.yaml
lib/core/presentation/resources/drawables.dart
```

ForgeKit never overwrites an existing destination asset during this operation.
It also avoids duplicate constants and reports filename collisions when two
files would create the same Dart identifier.

### `forgekit add flavor`

```sh
forgekit add flavor dev,staging,prod
```

Expected files:

```text
lib/
├── core/config/flavor_config.dart
├── main_dev.dart
├── main_staging.dart
└── main_prod.dart
```

Run one Dart entrypoint:

```sh
flutter run -t lib/main_dev.dart
```

Representative entrypoint:

```dart
import 'core/config/flavor_config.dart';
import 'main.dart' as app;

void main() {
  FlavorConfig.init(Flavor.dev);
  app.main();
}
```

This command scaffolds Dart-side flavors. Android `productFlavors`, iOS
schemes, signing, and store-specific configuration remain manual because they
vary significantly between applications.

### `forgekit add env` and `forgekit set env`

> **Do not put secrets in generated environment JSON.** Files under
> `assets/env/` are bundled application assets and can be extracted from a
> shipped client. They are suitable for public configuration such as base URLs,
> feature flags, and display settings—not private keys, signing material,
> passwords, or privileged API credentials. Flutter likewise warns that
> obfuscation does not protect secrets stored in an app; see
> [Obfuscate Dart code](https://docs.flutter.dev/deployment/obfuscate#limitations-and-warnings).

Create environment files:

```sh
forgekit add env dev,staging,prod
```

Expected files:

```text
assets/env/
├── dev.json
├── staging.json
└── prod.json

lib/core/config/env_config.dart
```

The assets directory is also registered in `pubspec.yaml`.

Representative `dev.json`:

```json
{
  "ENVIRONMENT": "dev",
  "API_BASE_URL": "https://dev.api.example.com"
}
```

Set one value:

```sh
forgekit set env API_BASE_URL https://dev.example.com --environment dev
```

Set the same value in every environment:

```sh
forgekit set env ENABLE_LOGGING true --all
```

ForgeKit rejects secret-like keys by default:

```sh
forgekit set env ACCESS_TOKEN abc123 --environment dev
```

Expected result:

```text
ACCESS_TOKEN looks like a secret or credential. ForgeKit refused to write it
to assets/env because bundled Flutter assets are public client data.
```

Some providers issue identifiers named `API_KEY` that are explicitly designed
to ship in clients and are protected with platform, application-id, origin, or
API restrictions. After confirming that contract and applying those
restrictions, acknowledge the exposure explicitly:

```sh
forgekit set env MAPS_API_KEY public_provider_key \
  --environment dev \
  --allow-public-value
```

`forgekit doctor` reports every secret-like key found in existing
`assets/env/*.json` files without reading or printing its value. `doctor --ci`
treats that warning as a failure so the key receives deliberate review.

Load an environment before `runApp`:

```dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await EnvConfig.load('dev');
  runApp(const App());
}
```

Read values:

```dart
final baseUrl = EnvConfig.string('API_BASE_URL');
final logging = EnvConfig.boolValue('ENABLE_LOGGING');
```

Values set by the CLI are stored as JSON strings. The generated accessors can
coerce common boolean and integer string values.

Transaction metadata records only the command path (`forgekit set env`), not
keys, values, URLs, paths, or options. Values typed on a command line can still
remain in shell history or CI logs. More importantly, anything accepted by this
command is shipped in the application. Use backend-issued runtime credentials,
platform secure storage for revocable session material, and server-side secret
management instead of bundling privileged credentials.

### `forgekit add i18n` and `forgekit add string`

Create localization configuration:

```sh
forgekit add i18n en,fr,es
```

Expected files:

```text
l10n.yaml
lib/l10n/
├── app_en.arb
├── app_fr.arb
└── app_es.arb
```

ForgeKit also:

- Adds `flutter_localizations` and `intl` to `pubspec.yaml`.
- Sets `flutter.generate: true`.
- Adds a starter `appTitle` message.

Add one value to every ARB file:

```sh
forgekit add string welcomeMessage "Welcome home"
```

Add or replace a value in one locale:

```sh
forgekit add string welcomeMessage "Bienvenue" --locale fr
```

Expected ARB entry:

```json
{
  "welcomeMessage": "Bienvenue",
  "@welcomeMessage": {
    "description": "TODO: describe welcomeMessage"
  }
}
```

Generate localization Dart code:

```sh
flutter gen-l10n
```

### `forgekit add test`

Generate state-management tests for a feature:

```sh
forgekit add test feature orders
```

Generate a model test:

```sh
forgekit add test model orders order
forgekit add test model money
```

Generate a function/use-case test:

```sh
forgekit add test function orders fetch_orders
```

Expected test tree:

```text
test/features/orders/
├── domain/
│   ├── entity/model/order_test.dart
│   └── usecase/fetch_orders_usecase_test.dart
└── presentation/manager/
    ├── orders_provider_test.dart
    └── orders_state_test.dart
```

The exact manager test name and implementation follow the configured state
manager. Use `--force` on a test subcommand to replace an existing generated
starter test.

Model and function tests are starters because constructors, fake repositories,
and meaningful expected values depend on the application domain.

### `forgekit test`

Run the project's Flutter tests, require every eligible production library in
Flutter's LCOV report, and enforce the configured line-coverage threshold:

```sh
forgekit test
```

ForgeKit runs `flutter test --coverage`, reads `coverage/lcov.info`, counts
unique executable lines reported under `lib/`, excludes common generated Dart
outputs such as `*.g.dart`, `*.freezed.dart`, `*.config.dart`, and
`*.mocks.dart`, and compares that reported result with `testing.coverage`.

Flutter can omit libraries that the test run never loads. ForgeKit therefore
compares LCOV source records with eligible `lib/**/*.dart` files and fails the
gate if any production library is absent. Generated outputs with supported
suffixes such as `.g.dart`, `.freezed.dart`, `.config.dart`, and `.mocks.dart`
remain excluded. This fail-closed check prevents an apparently high percentage
from hiding completely untested source files.

Expected passing result:

```text
Running: flutter test --coverage
00:03 +18: All tests passed!
✓ Coverage 86.42% (140/162 lines) meets the configured 80% threshold.
```

Expected threshold failure:

```text
Running: flutter test --coverage
00:03 +18: All tests passed!
✗ Coverage 74.69% (121/162 lines) is below the configured 80% threshold.
```

Both a failing Flutter test suite and a missed coverage threshold return a
non-zero process exit code, so the command can be used directly in CI:

```yaml
- name: Test and enforce coverage
  run: forgekit test
```

The command generates Flutter's normal coverage artifact:

```text
your_app/
├── coverage/
│   └── lcov.info
├── lib/
├── test/
└── forgekit.yaml
```

Forward Flutter test arguments after `--`:

```sh
forgekit test -- test/unit --name "serializes an order"
```

ForgeKit owns the coverage flags so that a caller cannot redirect or replace
the report being enforced. To run tests without collecting or checking
coverage—for example during a fast local edit loop—use:

```sh
forgekit test --no-coverage
```

CI should normally use the default coverage-enabled, fail-closed behavior.

### `forgekit rename feature`

```sh
forgekit rename feature orders purchases
```

ForgeKit renames:

- The Clean Architecture feature directory.
- Matching generated test directories.
- Filenames containing the old snake-case name.
- Feature-prefixed Dart identifiers.
- Dart `import`, `export`, and `part` URIs plus ForgeKit-owned route markers.

Example transformation:

```text
lib/features/orders/orders_repository.dart
→ lib/features/purchases/purchases_repository.dart

OrdersRepository
→ PurchasesRepository
```

String literals are deliberately preserved. This prevents a feature rename
from silently changing Retrofit endpoints, JSON keys, analytics names, deep
links, or user-facing copy. Review those contracts separately and change them
only when the external behavior should also change.

### `forgekit remove feature`

Interactive removal:

```sh
forgekit remove feature purchases
```

Non-interactive removal:

```sh
forgekit remove feature purchases --force
```

Expected deletion:

```text
lib/features/purchases/
test/features/purchases/
```

ForgeKit removes the feature folder, generated tests, and route imports and
registrations that carry ForgeKit ownership markers. User-authored routes and
similarly named features (for example, removing `orders` does not touch
`orders_archive`) are preserved. Review other user-authored cross-feature
dependencies after removal. Because removal is transactional, `forgekit
rollback` can restore the latest successful removal when no later edits
conflict.

### `forgekit sync widget`

After editing a shared widget in a project:

```sh
forgekit sync widget primary_button
```

Default source:

```text
lib/core/presentation/widgets/primary_button.dart
```

Default local destination:

```text
~/.forgekit/widgets/primary_button/
├── primary_button.dart
└── widget.json
```

Sync a file from another path:

```sh
forgekit sync widget primary_button \
  --path ./lib/design_system/primary_button.dart
```

Install it in another Flutter project:

```sh
forgekit add widget primary_button
```

ForgeKit rewrites `package:<source-project>/` imports to use the target
project's pubspec name.

### `forgekit registry`

Connect a Git-backed team registry:

```sh
forgekit registry connect https://github.com/your-org/forgekit_registry.git
```

ForgeKit accepts HTTPS, SSH, `file:` URLs, and local paths. It rejects plaintext
`http://` and `git://` transports, URL query strings/fragments, and URLs with
embedded usernames, passwords, or tokens. Keep GitHub/GitLab credentials in the
operating system's Git credential manager or an SSH agent; ForgeKit does not
write them to `~/.forgekit/registry.json`.

By default the repository is cloned into `~/.forgekit/registry`. Choose another
directory with:

```sh
forgekit registry connect <git-url> --path ../team_registry
```

Pull changes:

```sh
forgekit registry pull
```

Inspect connection and Git status:

```sh
forgekit registry status
```

Stage the registry's `widgets/` directory, commit, and push:

```sh
forgekit registry push
forgekit registry push --message "Add branded primary button"
```

Sync and push one widget in a single workflow:

```sh
forgekit sync widget primary_button --push
```

The registry is deliberately a normal Git repository. Authentication,
branching, review policy, and remote permissions are managed with normal Git
hosting tools.

### `forgekit set icon`

```sh
forgekit set icon ../design/app_icon.png
```

Expected changes:

```text
assets/icon/app_icon.png
pubspec.yaml
```

ForgeKit adds/configures `flutter_launcher_icons`, runs `flutter pub get`, and
then runs:

```sh
dart run flutter_launcher_icons
```

If `flutter pub get` or the icon generator fails, ForgeKit returns that non-zero
exit code and the surrounding `set` transaction restores the copied asset and
`pubspec.yaml`. Fix the reported upstream problem and rerun `forgekit set icon`.
Only native platform directories already present in the project are enabled.
The command fails before writing when neither `android/` nor `ios/` exists.

### `forgekit set splash`

```sh
forgekit set splash ../design/splash.png
forgekit set splash ../design/splash.png --color '#101828'
```

Expected changes:

```text
assets/splash/splash.png
pubspec.yaml
```

ForgeKit adds/configures `flutter_native_splash`, including an Android 12
section, runs `flutter pub get`, and then runs:

```sh
dart run flutter_native_splash:create
```

As with icon generation, an upstream failure returns a non-zero exit code and
restores the project transaction. Fix the reported error and rerun
`forgekit set splash`; CI will not receive a false success.

### `forgekit doctor`

Check the current project against its configured architecture:

```sh
forgekit doctor
```

Doctor checks required core files, feature files, class declarations,
state-manager naming, dependency annotations, Modular feature mounts, and
secret-like keys in bundled environment assets.

Example failure:

```text
Flutter ForgeKit CLI doctor: checking "shop_app"

  ✗ Missing core file: lib/core/domain/api/api_result.dart
  • [orders] manager is not annotated @injectable

1 error(s), 1 warning(s).
```

Treat warnings as failures in CI:

```sh
forgekit doctor --ci
```

Create missing files when ForgeKit has a safe canonical template:

```sh
forgekit doctor --fix
forgekit doctor --fix --dry-run
```

Safe automatic repair currently focuses on the Clean Architecture profile.
MVVM and Modular projects are checked, but ForgeKit does not yet attempt broad
automatic repairs for them.

### `forgekit diff`

Inspect the latest recorded generation:

```sh
forgekit diff
```

Expected clean result:

```text
Latest transaction 20260715T120000000Z (forgekit add feature):
  unchanged  lib/features/orders/...
No files have drifted since the latest generation.
```

If a generated file was edited afterward:

```text
  changed    lib/features/orders/presentation/manager/orders_provider.dart
1 generated file(s) changed after generation.
```

`diff` compares hashes; it does not print a line-by-line Git diff.

### `forgekit rollback`

Undo the latest successful generation:

```sh
forgekit rollback
```

ForgeKit deletes files created by that transaction and restores modified or
deleted files from `.forgekit/backups`.

If a file changed after generation, rollback stops:

```text
Rollback stopped because 1 file(s) changed after generation:
  lib/features/orders/orders_provider.dart
Review them first, or run "forgekit rollback --force".
```

After reviewing the conflict, explicitly overwrite later edits:

```sh
forgekit rollback --force
```

### `forgekit update`

```sh
forgekit update \
  --ref 0123456789abcdef0123456789abcdef01234567
```

Replace the example with the complete commit SHA reviewed by your team. ForgeKit
rejects branches, tags, `HEAD`, and abbreviated SHAs. It passes the exact commit
to Dart Pub through `--git-ref`, then runs setup to refresh the locally installed
bricks with the pinned Mason CLI version.

Running `forgekit update` without `--ref`, or passing `main`, fails before any
process is started.

Expected final output:

```text
Flutter ForgeKit CLI updated to commit 0123456789ab.
```

## Generated project structures

### Clean application

```text
lib/
├── core/
│   ├── di/
│   │   ├── core_module.dart
│   │   ├── core_module_container.dart
│   │   └── core_module_container.config.dart       # build_runner output
│   ├── domain/
│   │   ├── api/api_result.dart
│   │   └── usecase/use_case.dart
│   └── presentation/
│       ├── app/app.dart
│       ├── manager/
│       ├── theme/
│       ├── resources/
│       ├── utils/
│       └── widgets/
├── features/
├── services/
└── main.dart
```

### Complete Clean API feature after function generation

```text
lib/features/orders/
├── data/
│   ├── remote/
│   │   ├── dto/
│   │   │   ├── create_order_payload_dto.dart
│   │   │   ├── create_order_payload_dto.g.dart
│   │   │   ├── create_order_response_dto.dart
│   │   │   └── create_order_response_dto.g.dart
│   │   └── service/
│   │       ├── orders_api_service.dart
│   │       └── orders_api_service.g.dart
│   └── repository/orders_repository_impl.dart
├── domain/
│   ├── entity/
│   │   ├── model/create_order_response.dart
│   │   └── payload/create_order_payload.dart
│   ├── repository/orders_repository.dart
│   └── usecase/create_order_usecase.dart
├── presentation/
│   ├── manager/
│   │   ├── orders_provider.dart
│   │   └── orders_state.dart
│   ├── screens/orders_screen.dart
│   └── widgets/
└── di/orders_module.dart
```

Files ending in `.g.dart` are produced by `build_runner`, not written directly
by the ForgeKit template.

### MVVM feature

```text
lib/
├── config/di/orders_module.dart
├── data/
│   ├── repositories/orders_repository.dart
│   └── services/orders_api_service.dart
└── ui/orders/
    ├── view_models/
    │   ├── orders_state.dart
    │   └── orders_view_model.dart
    ├── widgets/orders_screen.dart
    └── orders_routes.dart                        # GoRouter mode
```

### Modular feature

```text
lib/modules/orders/
├── data/
│   ├── orders_api_service.dart
│   └── orders_repository.dart
├── presentation/
│   ├── orders_controller.dart
│   ├── orders_page.dart
│   └── orders_state.dart
└── orders_module.dart
```

## Generation safety and rollback

ForgeKit wraps the `add`, `config`, `doctor`, `init`, `import`, `remove`,
`rename`, and `set` command groups in a generation transaction when they run
inside a detected Flutter project.

`create app`, `setup`, `update`, `registry`, and `sync` are not covered by this
project transaction mechanism. `create app` instead refuses existing targets
and removes the new destination after a handled creation failure. Use normal
Git and remote-repository controls for the remaining external/global effects.

### What is recorded

On success, ForgeKit creates:

```text
.forgekit/
├── manifest.json
└── backups/
    └── <transaction-id>/
        ├── before/
        │   └── copies of modified/deleted original files
        └── transaction.json
```

`.forgekit/` is automatically added to the target project's `.gitignore`.

The transaction includes:

- The command path only, such as `forgekit add service` or `forgekit set env`.
  Positional arguments and option values are deliberately excluded.
- Created, modified, and deleted paths.
- Before and after SHA-256 hashes.
- Before and after line counts.
- Backups needed to restore the previous state.

### Failure restoration

If a generator returns a failure or generated Dart cannot be formatted,
ForgeKit restores the original project snapshot. This prevents half-generated
features or partially edited repositories in normal handled failures. An
abrupt process kill, machine failure, or external tool side effect cannot be
guaranteed to restore cleanly; Git remains the authoritative safety net.

### Important scope

Transactions apply to ForgeKit project mutations. External side effects such
as a remote Git push, package download, or global tool installation are outside
the target project snapshot.

To calculate changes and support restoration, ForgeKit snapshots project files
while excluding source-control metadata and common generated/cache trees such
as `.git/`, `.dart_tool/`, `.forgekit/`, `build/`, `coverage/`, Gradle caches,
CocoaPods, symlink caches, and DerivedData. Large source/assets trees can still
incur memory, disk, and startup overhead. ForgeKit retains the newest 20
transaction backup directories under `.forgekit/backups/` and prunes older
ones after a successful transaction.

Early development builds recorded complete commands. Updating ForgeKit does not
rewrite existing project history, so audit or remove old
`.forgekit/backups/*/transaction.json` files if those builds were used with
sensitive arguments. New transactions retain only the non-sensitive command
path.

## Using ForgeKit in a monorepo

ForgeKit uses Dart's own pub workspace resolver, including SDK-supported nested
workspaces and globs.

List the workspace:

```sh
forgekit workspace list
```

Target a Flutter package by pubspec name:

```sh
forgekit add feature orders --package mobile_app
```

Target it by workspace-relative path:

```sh
forgekit add feature orders --package apps/mobile
```

The global option may appear before the command:

```sh
forgekit --package mobile_app doctor --ci
```

Or after it:

```sh
forgekit doctor --ci --package mobile_app
```

ForgeKit validates that the target is a declared Flutter workspace package,
temporarily executes the command from that package directory, and restores the
CLI process's original directory afterward. It does not change the user's
shell directory.

Pub workspaces require Dart 3.6 or later. Workspace globs require Dart 3.11 or
later. See the
[Dart pub workspace documentation](https://dart.dev/tools/pub/workspaces).

## Mason bricks

Normal users should run `forgekit setup` instead of registering bricks
manually. The commands below are useful for CLI development and brick testing:

Direct `mason make` calls render a brick only. They bypass ForgeKit's route and
service orchestration, configuration validation, formatting transaction,
`--package` resolution, and rollback history. Use the `forgekit` commands for
normal application work.

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

The repository also contains `mason.yaml` for local resolution:

```sh
mason get
```

Run a brick directly:

```sh
mason make forge_feature \
  --name orders \
  --projectName my_app \
  --useRouter true \
  --useProvider true \
  --useRiverpod false \
  --useBloc false \
  --useCubit false \
  --runBuildRunner false
```

## Development

Install dependencies:

```sh
dart pub get
```

Run the CLI directly from source:

```sh
dart run bin/forgekit.dart --help
dart run bin/forgekit.dart --version
```

Format CLI source only:

```sh
dart format bin lib test
```

Do not run `dart format .` across the whole repository. Mason template Dart
files contain `{{mustache}}` placeholders and are intentionally invalid until
the brick renders them.

Analyze and test:

```sh
dart analyze
dart test
```

Test a generated Flutter project with normal tooling:

```sh
flutter pub get
dart run build_runner build
flutter analyze
flutter test
```

### Generated-application smoke tests

ForgeKit's own unit tests verify parsers and generators, but the smoke runner
goes further: it creates real Flutter applications and compiles the generated
result. Every case performs this sequence:

```text
forgekit setup
forgekit create app ... --platforms web
forgekit add feature smoke_feature --with-tests --no-build-runner
forgekit add screen smoke_feature details
forgekit add service analytics --driver generic --no-build-runner
optional storage-service generation
flutter pub get
dart run build_runner build
forgekit doctor --ci
flutter analyze
forgekit test --no-coverage
```

The smoke runner disables the configured coverage threshold because starter
tests prove that generated code compiles and executes; they are not intended
to give a newly scaffolded application 80% production coverage immediately.
Normal project CI should continue to run `forgekit test` with coverage enabled.

Run the four representative cases used for push and pull-request CI:

```sh
dart run tool/generated_app_smoke.dart
```

Those cases collectively cover:

```text
clean + provider + named routes       + shared_preferences
clean + cubit + go_router
mvvm  + riverpod + go_router          + flutter_secure_storage
modular + bloc + Modular routing      + both storage drivers
```

Expected final result:

```text
All 4 generated-app smoke case(s) passed.
```

Run one case while repairing a template:

```sh
dart run tool/generated_app_smoke.dart \
  --case clean_provider_named \
  --keep \
  --work-dir /tmp/forgekit-smoke
```

`--keep` preserves a successful run that uses the default temporary workspace.
A custom `--work-dir` is also preserved. Failed runs are always preserved, and
the runner prints their location so the generated source can be inspected
directly.

Run the complete 20-case architecture/state/router matrix:

```sh
dart run tool/generated_app_smoke.dart --all
```

The full matrix consists of Clean and MVVM combined with all four supported
state managers and both route styles, plus Modular combined with all four state
managers. `.github/workflows/generated-app-quality.yml` runs the four fast
representative cases and a real generated Android debug build on pushes and
pull requests. CLI analysis and unit tests run on Linux, macOS, and Windows.
The complete generation matrix runs every Sunday and whenever the workflow is
started manually.

Run the Android compilation check locally when the Android toolchain is
installed:

```sh
dart run tool/generated_app_smoke.dart \
  --case clean_provider_named \
  --build-android
```

### Repository layout

```text
forgekit_cli/
├── bin/forgekit.dart                  # executable entrypoint
├── lib/
│   ├── forgekit.dart                  # public package export
│   └── src/
│       ├── command_runner.dart
│       ├── commands/                  # command parsing and validation
│       └── *_service.dart             # generation and project operations
├── bricks/                            # Mason app/feature/widget/service bricks
├── doc/ARCHITECTURE_STANDARD.md
├── test/
├── tool/generated_app_smoke.dart      # real generated-app compiler matrix
├── .github/workflows/                 # CLI and generated-app CI
├── CHANGELOG.md
├── README.md
├── SECURITY.md
├── mason.yaml
└── pubspec.yaml
```

## Security notes

Report suspected vulnerabilities privately through the repository's
[security policy](SECURITY.md); do not disclose credentials or exploit details
in a public issue.

- ForgeKit runs with the current terminal user's permissions.
- Run it only in projects you trust and review generated code before shipping.
- JSON and local OpenAPI inputs are parsed locally. Remote OpenAPI entries
  require HTTPS; local files cannot fetch remote `$ref` documents unless
  `--allow-remote-references` is passed, and redirects remain same-origin.
- Generated networking does not install a request/response logger. Add only
  application-owned debug logging that redacts credentials and private bodies.
- Font generation downloads CSS and font files from Google Fonts.
- Asset, icon, and splash commands copy source files into the target project.
- `build_runner`, Flutter package tools, Mason, Git, and globally activated Dart
  tools execute as child processes where required.
- A shared widget registry can contain Dart source. Review registry changes and
  trust its maintainers before installing synced widgets. Registry connection
  rejects insecure transports and credential-bearing URLs.
- Generated `assets/env/*.json` files are public client configuration, not a
  secret store. ForgeKit rejects secret-like keys unless a publishable client
  value is explicitly acknowledged, and `doctor --ci` surfaces such keys for
  review. Command-line values can still remain in shell history.
- Transaction metadata stores only command paths and deliberately omits
  arguments and option values. Audit transaction files created by older
  development builds because they are not migrated automatically.
- Install public releases from a reviewed release tag; high-assurance automation
  can pin the full commit SHA behind that tag. `forgekit update` requires a full
  immutable commit SHA and rejects branches, tags, and abbreviated refs.
  `setup` activates the Mason CLI version tested with this ForgeKit release.
- GitHub Actions dependencies are pinned to full commit SHAs and workflow token
  permissions are read-only, following
  [GitHub's secure-use guidance](https://docs.github.com/en/actions/reference/security/secure-use#using-third-party-actions).
- Dart, Git, and Mason child processes are launched directly without a shell.
  Flutter's Windows batch wrapper is used only with validated ForgeKit inputs;
  forwarded test arguments containing Windows shell-control characters are
  rejected.
- ForgeKit is licensed under the
  [Apache License 2.0](LICENSE), including its explicit patent grant.
- `create app` accepts a Dart package name rather than a path, rejects every
  existing target type, and cleans its newly owned directory after handled
  failures.
- `rollback --force` can overwrite edits made after generation. Use `diff` and
  Git before forcing a rollback.

## Troubleshooting

| Problem | Explanation and fix |
| --- | --- |
| `forgekit: command not found` | Add `~/.pub-cache/bin` to `PATH`, then reactivate the package. |
| Mason cannot be executed | Run `forgekit setup`; ForgeKit activates and executes its pinned Mason version through Dart Pub rather than relying on a shell wrapper. |
| Mason cannot find a ForgeKit brick | Re-run `forgekit setup` after installing or updating the CLI. |
| `flutter` cannot be started | Install Flutter and ensure `flutter` is on `PATH`. |
| Generated code references missing `.g.dart` files | Run `dart run build_runner build`. |
| `build_runner` reports conflicting outputs | Review the conflicts, then use the appropriate `build_runner` cleanup option for the project. |
| A feature command generated in the wrong directory | Run project-level Mason commands from the Flutter package root, or use `--package` in a pub workspace. |
| Feature inference fails | Pass the feature explicitly, for example `forgekit add screen orders detail`. |
| Route generation fails or a route is missing | Current templates wire named, GoRouter, and Modular routes automatically. Restore the relevant ForgeKit route marker, verify `forgekit.yaml` matches the project, and rerun the command; do not maintain a second manual route system. |
| Service generation cannot insert initialization | Current templates initialize generated services automatically before `runApp`. Verify that `main.dart` still contains `// forgekit:service-initializers`, restore the marker if it was intentionally removed, and rerun the command. |
| Coverage fails even though the reported percentage is high | Inspect `coverage/lcov.info`; ForgeKit fails closed when an eligible production library is absent, even if the lines that were reported have high coverage. Add tests that load the missing library or exclude only genuinely generated outputs through the supported suffix rules. |
| Icon or splash generation fails | ForgeKit returns the upstream failure and restores the `set` transaction. Fix the Flutter/package error, then rerun the ForgeKit command. |
| `set env` rejects a provider key | Bundled assets cannot protect secrets. If the provider explicitly documents the key as publishable client configuration, restrict it at the provider and rerun with `--allow-public-value`; otherwise move it server-side. |
| `forgekit update` rejects a ref | Pass a reviewed complete 40- or 64-character commit SHA. Branches, tags, `HEAD`, and abbreviated SHAs are intentionally rejected. |
| Registry connection rejects a URL | Use HTTPS, SSH, or a local path without embedded credentials or query parameters. Configure authentication with the Git credential manager or SSH agent. |
| A forwarded test name is rejected on Windows | Remove `cmd.exe` control characters such as `&`, `|`, `%`, or `!`; Flutter is distributed as a Windows batch wrapper. |
| Font lookup fails | Check the exact family name on Google Fonts and quote names containing spaces. |
| OpenAPI import rejects the document | Confirm it is OpenAPI 3.0 or 3.1, uses a supported JSON media type, keeps local references below the entry directory, uses HTTPS for remote input, opts into trusted remote references when needed, and the project uses the Clean profile. |
| Rollback refuses to continue | Run `forgekit diff`, preserve or commit manual edits, then decide whether `rollback --force` is appropriate. |
| `--package` cannot find the app | Run `forgekit workspace list` and use the declared pubspec name or workspace-relative path. |

## Contributing

Bug reports and focused pull requests are welcome. Read
[CONTRIBUTING.md](CONTRIBUTING.md) for the supported development workflow,
quality gates, generated-app checks, and expectations for changes to templates
or file-writing behavior. Report security issues privately as described in
[SECURITY.md](SECURITY.md).

## License

Copyright 2026 Emmanuel Oluwadamilola.

Flutter ForgeKit CLI is licensed under the
[Apache License, Version 2.0](LICENSE). The license permits commercial and
private use, modification, and redistribution subject to its conditions, and
includes an explicit patent grant. It is provided without warranties or
conditions of any kind.

## Related

- [Flutter ForgeKit CLI Architecture Standard](doc/ARCHITECTURE_STANDARD.md)
- Flutter ForgeKit VS Code Extension: companion editor interface that dispatches
  commands to this CLI.
