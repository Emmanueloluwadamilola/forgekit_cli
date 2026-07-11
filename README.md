# ForgeKit

> A local Dart CLI for building Flutter applications with repeatable project
> structure, Clean Architecture conventions, and generator-backed workflows.

ForgeKit helps software teams turn a Flutter architecture standard into
consistent, executable commands. Instead of manually copying folders,
renaming files, wiring dependencies, and recreating the same feature patterns,
developers can scaffold apps, features, API operations, models, screens,
widgets, services, assets, flavors, launch icons, and splash screens from one
CLI.

Under the hood, ForgeKit combines Mason bricks with native Dart generators.
Brick-backed commands create known project structures, while Dart generators
parse JSON, update YAML, write strongly typed Dart code, and wire generated
files into the existing application. This keeps code generation predictable,
reviewable, and aligned with the ForgeKit Architecture Standard.

ForgeKit is local-first. It does not require an account, API key, or cloud
service. Commands run with the same network and filesystem access as the
current terminal process, including commands that download Google Fonts or run
package tools.

## Features

- Scaffold a complete Flutter app from the `forge_app` Mason brick.
- Add Clean Architecture features with data, domain, presentation, routing, and
  dependency-injection wiring.
- Generate API functions from pasted JSON, including DTOs, models, payloads,
  use cases, repositories, providers, and service methods.
- Generate standalone models, screens, shared widgets, services, and use cases.
- Add Google Fonts, assets, launch icons, splash screens, and build flavors.
- Run `doctor` checks against the ForgeKit Architecture Standard.
- Use the same CLI from the terminal or the companion VS Code extension.

## Requirements

- Dart SDK `>=3.0.0 <4.0.0`
- Flutter SDK for app generation and generated-project workflows
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

ForgeKit shells out to Mason for app, feature, widget, and service generation.
The `forgekit setup` command installs Mason when needed and registers the
included bricks globally so they can be used from any Flutter project.

You usually do not need to run `mason add` yourself. Use the manual commands
below only when you are developing ForgeKit from this repository, testing a
brick directly with Mason, or debugging `forgekit setup`.

```sh
mason add -g forge_app --path bricks/forge_app
mason add -g forge_feature --path bricks/forge_feature
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
| `forgekit setup` | Install Mason when needed and register ForgeKit's bundled bricks. |
| `forgekit create app <name>` | Create a new ForgeKit Flutter project. |
| `forgekit add feature <name>` | Add a Clean Architecture feature module. |
| `forgekit add function [feature] <name>` | Generate an API operation from JSON and wire it into a feature. |
| `forgekit add model [feature] <name>` | Generate a domain model and DTO from JSON. |
| `forgekit add screen [feature] <name>` | Add a screen with a route id. |
| `forgekit add widget <name>` | Generate a shared design-system widget. |
| `forgekit add service <name>` | Generate a cross-cutting service. |
| `forgekit add usecase <feature> <name>` | Generate one use case in an existing feature. |
| `forgekit add font <name>` | Download and register a Google Font. |
| `forgekit add asset <file-or-folder>` | Register assets and generate typed `Drawables` constants. |
| `forgekit add flavor <a,b,c>` | Create flavor config and flavor entrypoints. |
| `forgekit set icon <image>` | Configure app launcher icons. |
| `forgekit set splash <image>` | Configure the native splash screen. |
| `forgekit doctor` | Check the project against the architecture standard. |
| `forgekit update` | Check pub.dev for a newer CLI version and update globally. |

### Create an App

```sh
forgekit create app my_app
forgekit create app my_app --org com.example
forgekit create app my_app --org com.example --font Poppins
```

`create app` runs `flutter create`, then applies the `forge_app` brick.

### Add a Feature

```sh
forgekit add feature orders
forgekit add feature orders --router go_router
forgekit add feature orders --no-build-runner
```

The default router mode is `named`. Use `--router go_router` when the project
uses GoRouter.

### Add a Function from JSON

```sh
forgekit add function orders fetch_orders --method GET --path /orders
```

The command prompts for response JSON and optional request payload JSON. Press
Enter on an empty line to finish each JSON block.

### Add a Model from JSON

```sh
forgekit add model money
forgekit add model orders address
```

With one argument, ForgeKit writes a core model unless it can infer the feature
from the current directory. With two arguments, the first is the feature name.

### Add Assets

```sh
forgekit add asset ./logo.png
forgekit add asset ./icons --dir images --recursive
```

ForgeKit registers the asset path in `pubspec.yaml` and updates
`lib/core/presentation/resources/drawables.dart`.

## How It Works

```text
Terminal or VS Code
        |
        v
forgekit CLI
        |
        +-- Mason bricks: app, feature, widget, service
        |
        +-- Native generators: function, model, screen, asset, font,
            flavor, icon, splash, doctor, update
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
dart run build_runner build --delete-conflicting-outputs
flutter analyze
flutter test
```

## Security Notes

- ForgeKit runs with the permissions of the current terminal process.
- Only run it against projects and input files you trust.
- JSON pasted into generator prompts is parsed locally and written into generated
  Dart files.
- Asset and native setup commands copy files into the target project.
- Font downloads request CSS and font files from Google Fonts.
- `update` queries pub.dev and can run `dart pub global activate` through
  `pub_updater`.

## Troubleshooting

| Problem | Fix |
| --- | --- |
| `forgekit: command not found` | Add `~/.pub-cache/bin` to `PATH`, then reactivate with `dart pub global activate --source git https://github.com/Emmanueloluwadamilola/forgekit_cli.git`. |
| `Mason not found` | Run `forgekit setup`. |
| Mason cannot find a brick | Run `forgekit setup` to register the bundled bricks. |
| Generated code is missing `.g.dart` files | Run `dart run build_runner build --delete-conflicting-outputs`. |
| Feature inference fails | Pass the feature name explicitly, for example `forgekit add screen orders detail`. |
| Font lookup fails | Check the exact font name on Google Fonts and quote multi-word names. |

## Related

- [ForgeKit Architecture Standard](docs/ARCHITECTURE_STANDARD.md)
- ForgeKit VS Code Extension: companion repository for editor integration.
