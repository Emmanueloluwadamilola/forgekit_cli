# Flutter ForgeKit CLI

Flutter ForgeKit CLI scaffolds Flutter projects and generates code that keeps following the same
architecture as the project grows.

Starting a Flutter app means making the same decisions every time — folder
structure, state management, networking, dependency injection, then hand-writing
the boilerplate that connects them. ForgeKit does that once, records the choices
in a config file, and generates every later feature, screen, model, and service in
the same shape. It runs locally, wraps changes in transactions you can preview and
roll back, and produces plain Flutter code with no runtime dependency on ForgeKit
itself. It is for Flutter and Dart engineers who start projects often, or who work
on teams where consistency across a codebase matters more than per-file freedom.

- **Local-first.** No account, no API key, no hosted service, no telemetry.
- **Architecture-aware.** Clean, MVVM, or Flutter Modular; Provider, Riverpod,
  Bloc, or Cubit; GoRouter or named routes.
- **Reversible.** `--dry-run` previews, `diff` shows drift, `rollback` undoes.
- **No lock-in.** Remove ForgeKit and every project it generated still builds.

---

## Table of contents

- [Requirements](#requirements)
- [Installation](#installation)
- [Quick start](#quick-start)
- [How it works](#how-it-works)
- [Command reference](#command-reference)
- [Workflows](#workflows)
- [Configuration](#configuration)
- [Environment variables](#environment-variables)
- [Troubleshooting](#troubleshooting)
- [Uninstalling](#uninstalling)
- [Contributing](#contributing)
- [License](#license)

---

## Requirements

| Requirement | Version | Notes |
| --- | --- | --- |
| Dart SDK | `>=3.5.4 <4.0.0` | For the CLI itself |
| Flutter SDK | Any current stable | Required for app creation and generated workflows |
| Flutter-bundled Dart | `>=3.8.0` | Required by **generated** projects. `create app` checks this and refuses on an older toolchain |
| Git | Any | Used for installation, CLI updates, and shared registries |
| `~/.pub-cache/bin` on `PATH` | — | So the `forgekit` command resolves |

Network access is only needed for commands that download something: Google Fonts,
remote OpenAPI documents, CLI updates, and Git registries.

---

## Installation

ForgeKit is not published to pub.dev — `pubspec.yaml` sets `publish_to: none`.
Install it from Git or from a local checkout.

### From Git (recommended)

```sh
dart pub global activate --source git https://github.com/Emmanueloluwadamilola/forgekit_cli.git --git-ref v0.1.0 && dart pub global run forgekit:forgekit setup
```

Then add pub's bin directory to your `PATH`:

```sh
export PATH="$HOME/.pub-cache/bin:$PATH"   # add to ~/.zshrc or ~/.bashrc
forgekit --version
```

The one-liner calls `setup` through `dart pub global run` rather than the bare
`forgekit` name, so it works before `PATH` is configured. That is the most common
reason a fresh install appears to succeed and then reports `command not found`.

To pin more tightly than a tag, pass the full 40-character commit SHA to
`--git-ref`. See
[Dart's Git activation docs](https://dart.dev/tools/pub/cmd/pub-global#activating-a-package-with-git).

### From a local checkout

For contributors, or to run an unreleased revision:

```sh
git clone https://github.com/Emmanueloluwadamilola/forgekit_cli.git
cd forgekit_cli
dart pub get
dart pub global activate --source path .
forgekit setup
```

### `forgekit setup` is required

It is not optional and not idempotent-free:

- installs the tested Mason CLI version (`0.1.3`) if it is absent or wrong,
- copies the bundled bricks into `~/.forgekit/bricks`,
- registers those brick names in Mason's **global** registry.

Existing global registrations named `forge_app`, `forge_feature`, and the other
bundled `forge_*` names **are replaced**. If you maintain your own bricks under
those names, rename them first.

Verify the install:

```sh
forgekit doctor
```

---

## Quick start

From nothing to a running, architecture-conforming app:

```sh
# 1. Create the project (non-interactive; omit flags to be prompted)
forgekit create app my_app \
  --org com.example \
  --architecture clean \
  --state-management provider \
  --router go_router \
  --platforms android,ios

cd my_app

# 2. Resolve dependencies and run the generators
flutter pub get
dart run build_runner build

# 3. Add a feature — folders, layers, and route registration
forgekit add feature orders

# 4. Confirm the project still matches the architecture contract
forgekit doctor

# 5. Run it
flutter run
```

`create app` prompts for architecture, router, state management, and platforms
when you omit those flags **and** a terminal is attached. In CI or any piped
invocation it reports the flags you need instead of hanging.

---

## How it works

### Architecture profiles

The profile is chosen at `create app` time and stored in `forgekit.yaml`. It
determines the folder layout, the brick used for generation, and where generated
files land.

| Profile | Layout | Routing + DI |
| --- | --- | --- |
| `clean` | Feature-first `data` / `domain` / `presentation` under `lib/features/<name>/` | Named routes or GoRouter; `get_it` + `injectable` |
| `mvvm` | Views and ViewModels under `lib/ui/<name>/`, data under `lib/data/` | Named routes or GoRouter; `get_it` + `injectable` |
| `modular` | Self-contained modules under `lib/modules/<name>/` | Flutter Modular routes and module-scoped binds |

Two further values can appear in `forgekit.yaml` but cannot be created:
`lean` and `legacy`. `forgekit init` assigns them when it detects an existing
project that does not match a ForgeKit layout. Generation commands refuse to run
on them.

### Not every command supports every profile

This is the single most important thing to know before choosing a profile.

| Command | clean | mvvm | modular |
| --- | :---: | :---: | :---: |
| `create app` | ✅ | ✅ | ✅ |
| `add feature` | ✅ | ✅ | ✅ |
| `add screen` | ✅ | ✅ | ✅ |
| `add service` | ✅ | ✅ | ✅ |
| `add test feature` | ✅ | ✅ | ✅ |
| `add asset`, `add font` | ✅ | ✅ | ✅ |
| `add i18n`, `add string`, `add env` | ✅ | ✅ | ✅ |
| `set icon`, `set splash`, `set env` | ✅ | ✅ | ✅ |
| `add widget` (synced) | ✅ | ✅ | ✅ |
| `doctor` (check) | ✅ | ✅ | ✅ |
| `add model` | ✅ | ❌ | ❌ |
| `add function` | ✅ | ❌ | ❌ |
| `add usecase` | ✅ | ❌ | ❌ |
| `add test model`, `add test function` | ✅ | ❌ | ❌ |
| `add widget --starter` | ✅ | ❌ | ❌ |
| `import openapi` | ✅ | ❌ | ❌ |
| `rename feature`, `remove feature` | ✅ | ❌ | ❌ |
| `doctor --fix` | ✅ | ❌ | ❌ |

Unsupported combinations fail with an explanatory message before writing
anything. **Clean is the most complete profile.** If you need model, use-case, or
OpenAPI generation, choose it.

### Generated markers

Generated files contain comments such as `// forgekit:named-routes`,
`// forgekit:modules`, and `// forgekit:service-initializers`. ForgeKit inserts
later registrations at these markers. Deleting one breaks the next generation
that needs it — the command fails with a clear message rather than writing to the
wrong place.

### Transactions

Commands in the transactional set snapshot the project, run, and either keep or
restore the changes:

`add`, `config`, `doctor`, `init`, `import`, `remove`, `rename`, `set`

For those commands:

- `--dry-run` previews and restores.
- A non-zero exit restores everything the command changed.
- `forgekit diff` shows drift since the last generation.
- `forgekit rollback` restores the last generation.

`create app` is **not** transactional. It creates a new directory and removes it
if creation fails.

---

## Command reference

### Global flags

| Flag | Effect |
| --- | --- |
| `--version` | Print the CLI version |
| `--package <name-or-path>` | Target one package in a Dart pub workspace |
| `--dry-run` | Preview and restore instead of keeping changes |

`--package` is accepted by: `add`, `config`, `diff`, `doctor`, `init`, `import`,
`remove`, `rename`, `rollback`, `set`, `sync`, `test`.

`--dry-run` is accepted by: `add`, `config`, `doctor`, `init`, `import`,
`remove`, `rename`, `set`.

Any other combination is a usage error.

---

### `forgekit create app <name>`

Creates a Flutter project and overlays the ForgeKit architecture.

| Flag | Values | Default |
| --- | --- | --- |
| `--org` | Reverse-domain identifier | `com.forgecyberlabs` |
| `--architecture` | `clean`, `mvvm`, `modular` | prompts |
| `--state-management` | `provider`, `riverpod`, `bloc`, `cubit` | prompts |
| `--router` | `named`, `go_router` | prompts (not valid with `modular`) |
| `--platforms` | `android`, `ios`, `web`, `macos`, `windows`, `linux` | prompts |
| `--font` | A Google Font name | none |

```sh
forgekit create app my_app --org com.example --architecture clean \
  --state-management riverpod --router go_router --platforms android,ios --font Poppins
```

The project name must be a valid lowercase Dart package name. ForgeKit refuses to
create into an existing file, directory, or symlink.

---

### `forgekit init`

Detects an existing Flutter project's architecture and writes `forgekit.yaml`.

| Flag | Effect |
| --- | --- |
| `--profile` | Override the detected profile (`lean`, `clean`, `mvvm`, `modular`, `legacy`) |
| `--state-management` | Override the detected stack |
| `-f`, `--force` | Replace an existing `forgekit.yaml` |

```sh
cd existing_app
forgekit init --profile clean --state-management bloc
```

---

### `forgekit setup`

Installs the pinned Mason CLI and registers the bundled bricks. No flags.

```sh
forgekit setup
```

---

### `forgekit add feature <name>`

Generates a full feature for the project's profile and registers its route or
module.

| Flag | Effect |
| --- | --- |
| `--router` | `named` or `go_router`. Must match the project's router; not valid on `modular` |
| `--with-tests` | Also generate starter tests |
| `--no-build-runner` | Skip `build_runner` afterwards |

```sh
forgekit add feature orders --with-tests
forgekit add feature billing --no-build-runner
```

---

### `forgekit add screen [<feature>] <name>`

Adds a screen with a static route `id` and registers the route. Run from inside
`lib/features/<feature>/` to omit the feature name (clean profile only).

```sh
forgekit add screen orders order_detail
```

---

### `forgekit add model [<feature>] <name>`

**Clean only.** Generates a domain model and a `@JsonSerializable` DTO from JSON.
Reads the JSON from stdin — paste it and press Enter on an empty line, or pipe it.

| Flag | Effect |
| --- | --- |
| `--feature <name>` | Place it in a feature instead of core |
| `--with-tests` | Also generate a model test |
| `--no-build-runner` | Skip `build_runner` |

```sh
forgekit add model orders Order --with-tests

# Non-interactive
echo '{"id":1,"total":9.99}' | forgekit add model Order
```

---

### `forgekit add function [<feature>] <name>`

**Clean only.** Generates a complete API operation: retrofit endpoint, response
DTO and domain model, optional request payload, a use case, and the wiring through
repository and provider. Reads response/request JSON from stdin.

| Flag | Effect |
| --- | --- |
| `--method` | `GET`, `POST`, `PUT`, `PATCH`, `DELETE`. Prompts if omitted |
| `--path` | Endpoint path, e.g. `/auth/login`. Prompts if omitted |
| `--with-tests` | Also generate a use-case test |
| `--no-build-runner` | Skip `build_runner` |

```sh
forgekit add function orders fetch_orders --method GET --path /orders
```

`--method` and `--path` are required when no terminal is attached.

---

### `forgekit add usecase <feature> <name>`

**Clean only.** Writes a single `UseCase` stub. No flags.

```sh
forgekit add usecase orders cancel_order
```

> The generated use case is **not** annotated `@injectable`, so it is not
> registered in the DI graph. Add the annotation yourself, or use `add function`,
> which does register it.

---

### `forgekit add service <name>`

Generates a cross-cutting singleton in `lib/services/`, registers it in DI, and
initialises it before `runApp`.

| Flag | Values |
| --- | --- |
| `--driver` | `generic`, `shared_preferences`, `flutter_secure_storage` |
| `--no-build-runner` | Skip `build_runner` |

```sh
forgekit add service analytics --driver generic
forgekit add service secure_storage --driver flutter_secure_storage
```

Omitting `--driver` prompts in a terminal and falls back to `generic` otherwise.
The storage drivers generate complete typed implementations and add the package
dependency; `generic` generates a skeleton with an empty `init()`.

---

### `forgekit add widget <name>`

Installs a widget from your synced library, or generates a starter widget.

| Flag | Effect |
| --- | --- |
| `-f`, `--force` | Overwrite an existing widget |
| `--starter` | Generate the starter template instead of a synced widget (**clean only**) |

```sh
forgekit add widget status_badge
forgekit add widget primary_button --starter
```

---

### `forgekit add asset <file-or-folder>`

Copies an asset in, registers its folder in `pubspec.yaml`, and adds a typed
constant to the generated `Drawables` class.

| Flag | Effect |
| --- | --- |
| `--dir <subfolder>` | Subfolder under `assets/`. Defaults by file type |
| `-r`, `--recursive` | Include nested subfolders when given a directory |

```sh
forgekit add asset ~/design/logo.svg
forgekit add asset ~/design/icons --dir icons --recursive
```

Images (including `.svg`) default to `assets/images/`, `.json`/`.lottie` to
`assets/lottie/`, everything else to `assets/files/`.

---

### `forgekit add font <FontName>`

Downloads a Google Font's static weights, registers them in `pubspec.yaml`, and
sets the app's `fontFamily`. No flags.

```sh
forgekit add font Poppins
```

---

### `forgekit add flavor <a,b,c>`

Scaffolds Dart-side build flavors: a `FlavorConfig` and per-flavor
`main_<flavor>.dart` entrypoints. No flags.

```sh
forgekit add flavor dev,staging,prod
```

> **Dart-side only.** This does not create Android product flavors or iOS
> schemes, so `flutter run --flavor dev` will not work until you add those
> yourself.

---

### `forgekit add env <a,b,c>`

Scaffolds JSON-backed environment configuration files. No flags.

```sh
forgekit add env dev,staging,prod
```

---

### `forgekit add i18n <locales>`

Scaffolds Flutter localization with ARB files and `l10n.yaml`. No flags.

```sh
forgekit add i18n en,fr,es
```

Run `flutter gen-l10n` afterwards.

---

### `forgekit add string <key> <value>`

Adds a localized string to your ARB files.

| Flag | Effect |
| --- | --- |
| `-l`, `--locale` | Update one locale only. Defaults to all ARB files |

```sh
forgekit add string welcomeMessage "Welcome back"
forgekit add string welcomeMessage "Bon retour" --locale fr
```

---

### `forgekit add test feature|model|function`

Retro-fits starter tests for artifacts that already exist.

| Subcommand | Profiles | Flags |
| --- | --- | --- |
| `add test feature <name>` | all | `-f`, `--force` |
| `add test model [<feature>] <name>` | clean | `--feature <name>`, `-f`, `--force` |
| `add test function <feature> <name>` | clean | `-f`, `--force` |

```sh
forgekit add test feature orders
forgekit add test model orders Order --force
forgekit add test function orders fetch_orders
```

---

### `forgekit import openapi <file-or-url>`

**Clean only.** Generates typed API features from an OpenAPI 3.0/3.1 document.

| Flag | Effect |
| --- | --- |
| `--tag <tag>` | Only import operations with these tags (repeatable, comma-separated) |
| `--feature <name>` | Put every selected operation in one feature |
| `--base-url <url>` | Override the first server URL in the spec |
| `--no-tests` | Skip generated tests (they are on by default) |
| `-f`, `--force` | Replace features that already exist |
| `--allow-remote-references` | Allow a local spec to fetch HTTPS `$ref` documents |
| `--no-build-runner` | Skip `build_runner` |

```sh
forgekit import openapi ./openapi.yaml --tag orders,payments
forgekit import openapi https://api.example.com/openapi.json --feature catalog
```

Remote `$ref` resolution is off by default. When enabled, only HTTPS is allowed
and redirects must stay same-origin.

---

### `forgekit set icon|splash|env`

| Command | Flags | Effect |
| --- | --- | --- |
| `set icon <image>` | — | Launcher icons via `flutter_launcher_icons` |
| `set splash <image>` | `--color <hex>` (default `#ffffff`) | Splash via `flutter_native_splash` |
| `set env <KEY> <VALUE>` | `-e`, `--environment`; `--all`; `--allow-public-value` | Write an environment value |

```sh
forgekit set icon assets/icon/app_icon.png
forgekit set splash assets/splash/logo.png --color '#101418'
forgekit set env API_BASE_URL https://api.example.com --environment dev
forgekit set env FEATURE_X_ENABLED true --all
```

`set env` rejects secret-looking keys unless you pass `--allow-public-value` and
confirm the value is public client configuration. Bundled environment assets ship
inside the app binary — they are not a secret store.

---

### `forgekit rename|remove feature`

**Clean only.**

| Command | Flags |
| --- | --- |
| `rename feature <old> <new>` | — |
| `remove feature <name>` | `-f`, `--force` |

```sh
forgekit rename feature orders purchases
forgekit remove feature legacy_checkout --force
```

`remove feature` asks for confirmation and refuses to run without `--force` when
no terminal is attached.

> `rename feature` rewrites identifiers by **prefix match** across `lib/` and
> `test/`. A very short old name (for example `a`) will rewrite unrelated
> identifiers. Preview it with `forgekit --dry-run rename feature ...` first.

---

### `forgekit test`

Runs the Flutter test suite and enforces the coverage threshold from
`forgekit.yaml`.

| Flag | Effect |
| --- | --- |
| `--no-coverage` | Skip coverage collection and the threshold check |

```sh
forgekit test
forgekit test --no-coverage
forgekit test -- --name "OrdersProvider"
```

Arguments after `--` are forwarded to `flutter test`. Coverage-related flags
cannot be forwarded; use `forgekit.yaml` instead.

---

### `forgekit doctor`

Checks the project against the architecture standard.

| Flag | Effect |
| --- | --- |
| `--ci` | Exit non-zero on any issue, warnings included |
| `--fix` | Create missing standard files where safe (**clean only**) |

```sh
forgekit doctor
forgekit doctor --fix
forgekit doctor --ci     # for pipelines
```

Without `--ci`, `doctor` exits non-zero only on errors.

---

### `forgekit diff` / `forgekit rollback`

| Command | Flags | Effect |
| --- | --- | --- |
| `diff` | — | Show drift since the last generation |
| `rollback` | `-f`, `--force` | Restore the last generation |

```sh
forgekit diff
forgekit rollback
forgekit rollback --force   # even if generated files changed afterwards
```

---

### `forgekit config show|set|validate`

```sh
forgekit config show
forgekit config set testing.coverage 90
forgekit config validate
```

> `config set` rewrites `forgekit.yaml` from ForgeKit's template. Comments and
> unrecognised keys are **not preserved**.

---

### `forgekit sync widget <name>` / `forgekit registry`

Share widgets across projects through a local library and an optional Git-backed
registry.

| Command | Flags |
| --- | --- |
| `sync widget <name>` | `-p`, `--path <file>`; `--push` |
| `registry connect <git-url>` | `--path <dir>` (default `~/.forgekit/registry`) |
| `registry pull` | — |
| `registry push` | `-m`, `--message` |
| `registry status` | — |

```sh
forgekit sync widget status_badge
forgekit registry connect git@github.com:acme/forgekit-registry.git
forgekit sync widget status_badge --push
forgekit registry pull
```

Registry remotes must be secure and must not embed credentials.

---

### `forgekit workspace list`

Lists packages in a Dart pub workspace.

| Flag | Effect |
| --- | --- |
| `--json` | Machine-readable output |

```sh
forgekit workspace list
forgekit workspace list --json
```

This is currently the only command with JSON output.

---

### `forgekit update --ref <sha>`

Reinstalls the CLI from a pinned immutable Git commit. The `--ref` value must be
a full 40- or 64-character hexadecimal SHA; branches and short SHAs are rejected.

```sh
forgekit update --ref 3f6c1d2e9b7a5c4f8e0d1a2b3c4d5e6f70819a2b
```

---

### `forgekit uninstall`

Removes everything `setup` installed: the Mason brick registrations,
`~/.forgekit`, and the executable.

| Flag | Effect |
| --- | --- |
| `--dry-run` | Print the plan, change nothing |
| `-f`, `--force` | Skip confirmation. Required when no terminal is attached |
| `--keep-widgets` | Preserve your synced widget library |
| `--remove-mason` | Also remove the Mason CLI and its cache |
| `--clean-project` | Also delete `forgekit.yaml` and `.forgekit/` from the current project |

```sh
forgekit uninstall --dry-run
forgekit uninstall --keep-widgets
```

See [Uninstalling](#uninstalling).

---

## Workflows

### 1. New app with a REST backend

```sh
forgekit create app storefront --org com.example --architecture clean \
  --state-management bloc --router go_router --platforms android,ios
cd storefront
flutter pub get

# Environments and API base URL
forgekit add env dev,staging,prod
forgekit set env API_BASE_URL https://api.example.com --environment prod
forgekit set env API_BASE_URL https://staging-api.example.com --environment staging

# Generate the whole API surface from the spec
forgekit import openapi ./openapi.yaml --tag catalog,orders

# Branding
forgekit add font Inter
forgekit set icon assets/icon/app_icon.png
forgekit set splash assets/splash/logo.png --color '#0B0B0F'

forgekit doctor
forgekit test
```

### 2. Adding a feature to an existing ForgeKit project

```sh
forgekit --dry-run add feature wishlist        # preview
forgekit add feature wishlist --with-tests     # commit to it

forgekit add screen wishlist wishlist_detail

# Endpoint + DTO + model + use case + wiring, from pasted JSON
forgekit add function wishlist fetch_wishlist --method GET --path /wishlist

forgekit doctor
forgekit test
```

If anything looks wrong:

```sh
forgekit diff
forgekit rollback
```

### 3. Adopting ForgeKit in an existing app

```sh
cd existing_app
forgekit init                 # detects and writes forgekit.yaml
forgekit config show          # confirm the detected values
forgekit doctor               # see what does not match the standard
forgekit doctor --fix         # create missing standard files (clean only)
```

If detection assigns `lean` or `legacy`, generators will refuse to run. Either
migrate the layout to match a supported profile, or set the profile explicitly
with `forgekit init --profile clean --force` once the layout matches.

### 4. Monorepo / pub workspace

```sh
forgekit workspace list
forgekit --package mobile_app add feature orders
forgekit --package mobile_app test
forgekit --package design_system doctor
```

`--package` accepts a package name or a workspace-relative path. One command
targets one package; there is no recursive mode.

---

## Configuration

`forgekit.yaml` sits at the project root and is created by `create app` or
`init`.

```yaml
version: 1
architecture: clean
state_management: provider
router: named
dependency_injection: injectable
models: json_serializable
api_client: retrofit
generation:
  format: true
  build_runner: true
testing:
  coverage: 80
```

| Key | Values | Default |
| --- | --- | --- |
| `version` | `1` | `1` |
| `architecture` | `clean`, `mvvm`, `modular`, `lean`, `legacy` | `clean` |
| `state_management` | `provider`, `riverpod`, `bloc`, `cubit` | `provider` |
| `router` | `named`, `go_router`, `modular` | `named` |
| `dependency_injection` | `injectable`, `flutter_modular` | `injectable` |
| `models` | `json_serializable` | `json_serializable` |
| `api_client` | `retrofit` | `retrofit` |
| `generation.format` | `true`, `false` | `true` |
| `generation.build_runner` | `true`, `false` | `true` |
| `testing.coverage` | `0`–`100` | `80` |

Cross-field rules enforced by `config validate`:

- `architecture: modular` requires `router: modular` and
  `dependency_injection: flutter_modular`.
- Every other architecture requires `dependency_injection: injectable` and a
  non-`modular` router.

`config set` also accepts short aliases for the nested keys: `coverage`,
`format`, and `build_runner`.

```sh
forgekit config set coverage 90            # same as testing.coverage
forgekit config set build_runner false     # same as generation.build_runner
```

---

## Environment variables

| Variable | Effect |
| --- | --- |
| `FORGEKIT_HOME` | Override ForgeKit's data directory. Default `~/.forgekit`, or `%APPDATA%\ForgeKit` on Windows |
| `FORGEKIT_DEBUG=1` | Include stack traces in unexpected-error output |
| `MASON_CACHE` | Override where Mason stores global brick registrations |

ForgeKit also reads `HOME`, `USERPROFILE`, `APPDATA`, and `LOCALAPPDATA` to
resolve those defaults per platform.

### What lives where

| Path | Contents |
| --- | --- |
| `~/.pub-cache/bin/forgekit` | The executable |
| `~/.forgekit/bricks/` | Installed copies of the bundled Mason bricks |
| `~/.forgekit/widgets/` | Your synced widget library |
| `~/.forgekit/registry/` | Clone of a connected shared registry |
| `~/.mason-cache/global/` | Mason's global brick registrations |
| `<project>/forgekit.yaml` | Per-project configuration |
| `<project>/.forgekit/` | Generation manifest and rollback snapshots (last 20) |

Add `.forgekit/` to your project's `.gitignore`. Projects created by newer
versions include it already.

---

## Troubleshooting

**`Could not find a command named "..."`**
Your installed binary predates the command. Reinstall, or activate from a local
checkout: `dart pub global activate --source path .`

**`command not found: forgekit` right after installing**
`~/.pub-cache/bin` is not on your `PATH`:

```sh
export PATH="$HOME/.pub-cache/bin:$PATH"
```

**`Failed to create app "x"` / `Failed to add feature "x"`**
Usually `forgekit setup` has not run, so the bricks are not registered. Run
`forgekit setup`, then `forgekit doctor` to confirm.

**`No pubspec.yaml found in this or any parent directory`**
Run the command from inside a Flutter project.

**`No forgekit.yaml found. Run "forgekit init" first.`**
The project has no ForgeKit config. Run `forgekit init`.

**The command refuses on `mvvm` or `modular`**
That generator is clean-only. See
[the profile matrix](#not-every-command-supports-every-profile).

**`--router is not available for modular projects`**
Flutter Modular owns routing. Drop the flag.

**`This project uses router "X"`**
`add feature --router` must match `forgekit.yaml`. Omit the flag to use the
project's router.

**A prompt hangs, or `StdinException` in CI**
Supply the values as flags. `create app` needs `--architecture`, `--router`,
`--state-management`, and `--platforms`; `add function` needs `--method` and
`--path`; `add model` needs JSON piped on stdin; `remove feature` needs
`--force`.

**`Could not find the marker ...` / route registration fails**
A `// forgekit:*` marker was removed or reformatted. Restore it, or run
`forgekit doctor` to see which file is affected.

**`build_runner` fails after generation**
The whole command's changes are rolled back, including the code that generated
correctly. Fix the underlying build error, then re-run with
`--no-build-runner` and run `dart run build_runner build` yourself to see the
full output.

**Coverage threshold fails on a new project**
A freshly generated app has few tests. Lower the threshold
(`forgekit config set coverage 0`) or run `forgekit test --no-coverage` until you
have a suite.

**Debugging anything else**

```sh
FORGEKIT_DEBUG=1 forgekit <command>
```

---

## Uninstalling

```sh
forgekit uninstall --dry-run   # see the plan
forgekit uninstall
```

If your installed version has no `uninstall` command, do it by hand — **order
matters**, because unregistering after deleting the brick directories leaves
Mason pointing at paths that no longer exist:

```sh
for b in forge_app forge_app_mvvm forge_app_modular forge_feature \
         forge_feature_mvvm forge_feature_modular forge_widget forge_service; do
  mason remove -g "$b" 2>/dev/null
done
dart pub global deactivate forgekit
rm -rf ~/.forgekit
```

Back up `~/.forgekit/widgets` first if you have synced widgets.

Mason is left installed — `forgekit setup` only installs it when absent, so it may
predate ForgeKit on your machine. Remove it only if nothing else needs it:

```sh
dart pub global deactivate mason_cli && rm -rf ~/.mason-cache
```

Projects are unaffected. `forgekit.yaml` and `.forgekit/` are inert without the
CLI and can be deleted whenever you like.

Full detail: [doc/UNINSTALL.md](doc/UNINSTALL.md).

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for the proposal process and the required
checks. In short:

```sh
dart pub get
dart format --output=none --set-exit-if-changed bin lib test tool
dart analyze
dart test
dart run tool/generated_app_smoke.dart --case clean_provider_named
```

Do not run `dart format .` — the Mason templates under `bricks/` contain Mustache
expressions and are not valid Dart until rendered.

The architecture contract every generator must satisfy is
[doc/ARCHITECTURE_STANDARD.md](doc/ARCHITECTURE_STANDARD.md). If a generator and
that document disagree, the document wins: update it first, then the code.

---

## License

Apache-2.0. See [LICENSE](LICENSE).
