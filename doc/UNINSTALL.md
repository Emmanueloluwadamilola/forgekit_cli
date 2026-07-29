# Removing Flutter ForgeKit CLI

```sh
forgekit uninstall
```

That is the whole thing. It unregisters the bundled Mason bricks, deletes
ForgeKit's data directory, and deactivates the executable — in that order,
which matters (see [Why order matters](#why-order-matters)).

**Your generated projects are unaffected.** ForgeKit produces plain Flutter
code with ordinary pub dependencies. Once it is gone, every app it generated
still builds, runs, and ships. Nothing in a generated project imports ForgeKit
or calls back into it.

## See what it will do first

```sh
forgekit uninstall --dry-run
```

Prints the exact list and changes nothing.

## Options

| Flag | Effect |
| --- | --- |
| `--dry-run` | Print the plan, change nothing |
| `-f`, `--force` | Skip the confirmation prompt. Required in CI, where the prompt cannot run |
| `--keep-widgets` | Preserve `~/.forgekit/widgets`, your synced widget library |
| `--remove-mason` | Also remove the Mason CLI and its cache |
| `--clean-project` | Also delete `forgekit.yaml` and `.forgekit/` from the current project |

Two defaults are deliberately conservative:

**Mason is kept.** `forgekit setup` installs `mason_cli` only when it is absent
or at the wrong version, so on some machines ForgeKit installed it and on others
it was already there for unrelated work. ForgeKit cannot tell which, so it does
not guess. Add `--remove-mason` if nothing else needs it.

**Your widget library is deleted.** `~/.forgekit/widgets` is the one
irreplaceable thing in the data directory. Pass `--keep-widgets` to keep it, or
back it up first:

```sh
cp -r ~/.forgekit/widgets ~/Desktop/forgekit-widgets-backup
```

## Typical invocations

```sh
# Interactive, keeping Mason and the widget library
forgekit uninstall --keep-widgets

# Everything, no prompts — CI or a scripted teardown
forgekit uninstall --force --remove-mason

# Also clean the project you are standing in
forgekit uninstall --force --clean-project
```

## Why order matters

Bricks are unregistered **before** their directories are deleted. The other way
round leaves entries in Mason's global config pointing at paths that no longer
exist, and `mason list -g` then reports broken bricks until someone edits that
config by hand. This is the main reason the command exists rather than a
copy-paste snippet.

Self-deactivation runs **last**, because it removes the executable running the
command. On macOS and Linux this completes cleanly. On Windows a running
executable cannot be deleted, so the final step may fail — the command detects
that and prints the one command to finish with:

```sh
dart pub global deactivate forgekit
```

## Safety guard

`FORGEKIT_HOME` is user-controlled, so uninstall refuses to delete a path that
is the filesystem root, an immediate child of it, or your home directory. A
stray `export FORGEKIT_HOME=$HOME` cannot turn uninstall into `rm -rf ~`; it
reports the refusal and exits non-zero instead.

---

## Doing it by hand

Everything below is what the command automates. You only need this if
`forgekit` itself will not run.

## macOS and Linux

### 1. Unregister the bundled bricks

```sh
for brick in forge_app forge_app_mvvm forge_app_modular \
             forge_feature forge_feature_mvvm forge_feature_modular \
             forge_widget forge_service; do
  mason remove -g "$brick"
done
```

Bricks that were never registered report an error you can ignore.

### 2. Remove the ForgeKit executable

```sh
dart pub global deactivate forgekit
```

### 3. Remove ForgeKit's data directory

```sh
rm -rf ~/.forgekit
```

This holds the installed brick copies, your synced widget library
(`~/.forgekit/widgets`), and any shared registry clone
(`~/.forgekit/registry` plus `registry.json`).

If you set `FORGEKIT_HOME`, delete that path instead:

```sh
rm -rf "$FORGEKIT_HOME"
```

**Back up your widget library first if you want to keep it:**

```sh
cp -r ~/.forgekit/widgets ~/Desktop/forgekit-widgets-backup
```

### 4. Remove Mason — only if ForgeKit installed it

`forgekit setup` runs `dart pub global activate mason_cli` if Mason is absent or
at the wrong version. **Skip this step if you used Mason before ForgeKit**, or
if any other tool on your machine depends on it.

```sh
dart pub global deactivate mason_cli
rm -rf ~/.mason-cache
```

### 5. Verify

```sh
which forgekit          # expect: not found
dart pub global list    # expect: no forgekit, no mason_cli
ls ~/.forgekit          # expect: No such file or directory
```

---

## Windows (PowerShell)

```powershell
# 1. Unregister the bundled bricks
$bricks = @(
  'forge_app','forge_app_mvvm','forge_app_modular',
  'forge_feature','forge_feature_mvvm','forge_feature_modular',
  'forge_widget','forge_service'
)
foreach ($b in $bricks) { mason remove -g $b }

# 2. Remove the executable
dart pub global deactivate forgekit

# 3. Remove ForgeKit's data directory
Remove-Item -Recurse -Force "$env:APPDATA\ForgeKit"

# 4. Only if ForgeKit installed Mason for you
dart pub global deactivate mason_cli
Remove-Item -Recurse -Force "$env:APPDATA\Mason"
Remove-Item -Recurse -Force "$env:LOCALAPPDATA\Mason"   # if present

# 5. Verify
Get-Command forgekit -ErrorAction SilentlyContinue
dart pub global list
```

Mason's cache is at `%APPDATA%\Mason\Cache` or `%LOCALAPPDATA%\Mason\Cache`
depending on which existed when it was installed. Check both.

---

## Per-project leftovers

`forgekit uninstall --clean-project` handles the project you are standing in.
It never searches beyond that, deliberately — walking the filesystem deleting
files by name is not something an uninstaller should do unasked.

For other projects, the paths are below. Removing them is optional — a project
keeps building either way.

| Path | What it is | Safe to delete? |
| --- | --- | --- |
| `forgekit.yaml` | Records the architecture, state management, router, and generation settings | Yes. Nothing at runtime reads it |
| `.forgekit/` | Rollback snapshots and the generation manifest | Yes, but you lose `forgekit rollback` history |

To clear them from one project:

```sh
rm -f forgekit.yaml
rm -rf .forgekit
```

Across several projects:

```sh
find ~/dev -maxdepth 3 -name forgekit.yaml -print   # review first
find ~/dev -maxdepth 3 -name forgekit.yaml -delete
find ~/dev -maxdepth 3 -type d -name .forgekit -exec rm -rf {} +
```

Run the `-print` pass before the destructive one.

Everything else ForgeKit generated — `lib/features/`, `lib/services/`,
`assets/`, the dependencies in `pubspec.yaml`, the `// forgekit:` marker
comments — is ordinary project code. Keep it. The marker comments are inert
without the CLI; they only matter if you reinstall and want generation to resume
inserting at the same points.

---

## The VS Code extension

```sh
code --uninstall-extension forgecyberlabs.forgekit
```

Or find "ForgeKit" in the Extensions panel and choose Uninstall. If you
installed the local `.vsix`, the same command applies.

---

## Pub cache remnants

`dart pub global deactivate` removes the executable and the global package
reference, but the downloaded source may remain in `~/.pub-cache/git/`
(ForgeKit is installed from Git) or `~/.pub-cache/hosted/` (Mason). This is
harmless — pub reuses and prunes it — but to reclaim the space:

```sh
dart pub cache clean
```

That clears the cache for **every** Dart and Flutter package on your machine,
not just ForgeKit. Your next `pub get` in any project re-downloads what it
needs. Only worth doing if you are reclaiming disk space deliberately.
