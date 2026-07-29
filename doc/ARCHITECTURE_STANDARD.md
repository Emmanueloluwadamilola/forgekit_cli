# Flutter ForgeKit CLI Architecture Standard

This document is the **single source of truth** for how Flutter ForgeKit CLI
apps are structured. Every generator (Mason brick, `forgekit` CLI, and a
compatible editor integration) must produce code that conforms to this
standard.

> If a generator and this document disagree, this document wins. Update the
> document first, then the generators.

## Architecture profiles

Flutter ForgeKit CLI supports three project-wide architecture profiles. The
selected value is stored in `forgekit.yaml` and controls both app and feature
generation.

| Profile | Primary organization | Routing and dependency injection |
| --- | --- | --- |
| `clean` | Feature-first `data/domain/presentation` layers | Named routes or GoRouter; GetIt and Injectable |
| `mvvm` | `ui/<feature>` Views and ViewModels over `data` repositories and services | Named routes or GoRouter; GetIt and Injectable |
| `modular` | Self-contained `modules/<feature>` packages | Flutter Modular v7 routes and module-scoped dependencies |

The detailed contract below describes the default `clean` profile. MVVM uses
Flutter's recommended UI and data-layer separation with a View paired to a
ViewModel. Modular features own their mount path, routes, data dependencies,
controller, state, and page; the root `appModule` is the composition map.

---

## 1. Stack (locked)

| Concern            | Choice                                                              | Notes |
|--------------------|--------------------------------------------------------------------|-------|
| Architecture       | Clean Architecture, feature-first (default profile)                | data / domain / presentation inside each feature |
| State management   | Provider, Riverpod, Bloc, or Cubit                                  | selected project-wide in `forgekit.yaml`; Provider uses the Flutter ForgeKit CLI `CustomProvider` base and every option generates a paired `*State` object |
| Dependency injection | `get_it` + `injectable`                                          | one `@module` per feature, generated container |
| Networking         | `dio` + `retrofit`                                                   | an `ApiResult<T>` wrapper; authentication, redacted debug logging, and token refresh remain application-owned |
| Serialization      | `json_serializable` + `json_annotation`                            | no `freezed`; explicit DTO → domain conversion |
| Routing            | GoRouter or named routes + static `.id` on screens                  | see §7; GoRouter is the interactive default for new Clean and MVVM apps |
| Spacing            | `gap`                                                              | `Gap(16)` instead of `SizedBox` |
| Responsive         | `flutter_screenutil` (optional per project)                        | `designSize: Size(360, 690)` |

### Locked dependency versions (baseline)

```yaml
provider: ^6.1.5
flutter_riverpod: ^3.3.2 # when the Riverpod profile is selected
flutter_bloc: ^9.1.1     # when the Bloc or Cubit profile is selected
get_it: ^9.2.1
injectable: ^3.0.0
dio: ^5.10.0
retrofit: ^4.9.2
json_annotation: ^4.12.0
gap: ^3.0.1
flutter_secure_storage: ^10.3.1
shared_preferences: ^2.5.5 # when a SharedPreferences storage service is added
dartz: ^0.10.1            # optional, for Either-style error handling

# Firebase, added by `forgekit add firebase` (see §6.1). Unreleased: these
# baselines are taken from pub.dev but not yet smoke-tested.
firebase_core: ^4.12.1           # any Firebase capability
firebase_crashlytics: ^5.2.3     # --features crashlytics
firebase_analytics: ^12.4.2      # --features analytics
firebase_messaging: ^16.2.0      # --features push
firebase_remote_config: ^6.4.0   # --features remote_config

# dev
build_runner: ^2.15.1
injectable_generator: ^3.0.2
retrofit_generator: ^10.2.6
json_serializable: ^6.14.0
```

The detailed examples below use the Provider profile.
Riverpod, Bloc, and Cubit generators preserve the same feature-first layer
boundaries while replacing the presentation manager and widget bindings.

---

## 2. Top-level `lib/` layout

```
lib/
├── core/
│   ├── di/
│   │   ├── core_module.dart                 # @module: Dio and baseline secure storage
│   │   ├── core_module_container.dart        # getIt + configureDependencies()
│   │   └── core_module_container.config.dart # GENERATED
│   ├── domain/
│   │   ├── api/
│   │   │   └── api_result.dart               # ApiResult<T> sealed wrapper
│   │   └── usecase/
│   │       └── use_case.dart                 # UseCase<Output, Params> base
│   └── presentation/
│       ├── app/
│       │   └── app.dart                      # root MaterialApp + routes
│       ├── manager/
│       │   ├── custom_provider.dart          # ChangeNotifier base
│       │   ├── custom_state.dart             # view-state base + Status enum
│       │   └── theme_provider.dart           # light/dark switching
│       ├── theme/
│       │   ├── app_theme.dart                # AppTheme mixin: lightTheme()/darkTheme()
│       │   ├── text_theme.dart               # MyTextTheme
│       │   └── colors/
│       │       └── colors.dart               # color constants
│       ├── resources/
│       │   └── drawables.dart                # created by asset generation
│       ├── utils/extensions/
│       │   └── navigation.dart               # named-route navigation helpers
│       └── widgets/                          # starter shared widgets
│           ├── button.dart
│           ├── clickable.dart
│           └── svg_image.dart
├── features/
│   └── <feature>/                            # see §3
├── services/                                 # generated cross-cutting singletons (see §6)
│   ├── analytics_service.dart                # example generic initialized service
│   ├── local_storage_service.dart            # optional SharedPreferences driver
│   └── secure_storage_service.dart           # optional secure-storage driver
└── main.dart
```

**Decision locked:** services live in `lib/services/` (top-level), not
`lib/core/services/`.

---

## 3. Complete Clean feature layout

The bare `add feature` command creates the API service, repository contract and
implementation, presentation manager/state, primary screen, route integration,
and DI module. Later `add function`, `add model`, `add usecase`, and `add widget`
commands fill the corresponding folders. For a feature named `orders`, the
resulting feature can grow into this structure (snake_case files and PascalCase
classes):

```
features/orders/
├── data/
│   ├── remote/
│   │   ├── dto/
│   │   │   ├── order_dto.dart                # @JsonSerializable, *.g.dart
│   │   │   └── create_order_payload_dto.dart
│   │   └── service/
│   │       └── orders_api_service.dart        # @RestApi retrofit client, *.g.dart
│   └── repository/
│       └── orders_repository_impl.dart        # implements domain repo, maps DTO→model
├── domain/
│   ├── entity/
│   │   ├── model/
│   │   │   └── order.dart                      # plain domain model
│   │   └── payload/
│   │       └── create_order_payload.dart       # request input
│   ├── repository/
│   │   └── orders_repository.dart              # abstract
│   └── usecase/
│       └── fetch_orders_usecase.dart           # extends UseCase<List<Order>, NoParams>
├── presentation/
│   ├── manager/
│   │   ├── orders_provider.dart                # extends CustomProvider
│   │   └── orders_state.dart                   # extends CustomState
│   ├── screens/
│   │   └── orders_screen.dart                  # static `id`; ChangeNotifierProvider
│   ├── orders_routes.dart                      # go_router only (--router=go_router); omitted for named routes
│   └── widgets/
│       └── order_card.dart
└── di/
    └── orders_module.dart                      # @module registering api service + repo
```

### Data flow (one direction)

```
Screen → Provider → UseCase → Repository(abstract)
                                   ↑ impl
                          RepositoryImpl → ApiService (dio/retrofit)
                                   ↓
                          DTO → (mapper) → domain Model → ApiResult<Model>
                                   ↑
Screen ← Provider (notifyListeners) ← state updated from ApiResult
```

---

## 4. Canonical base classes (names are contractual)

These names must be identical everywhere; generators depend on them.

### `core/domain/api/api_result.dart`

```dart
sealed class ApiResult<T> {
  const ApiResult();
}

class Success<T> extends ApiResult<T> {
  final T data;
  const Success(this.data);
}

class Failure<T> extends ApiResult<T> {
  final String message;
  final int? statusCode;
  const Failure(this.message, {this.statusCode});
}
```

### `core/domain/usecase/use_case.dart`

```dart
abstract class UseCase<Output, Params> {
  Future<ApiResult<Output>> call(Params params);
}

class NoParams {
  const NoParams();
}
```

### `core/presentation/manager/custom_provider.dart`

```dart
import 'package:flutter/material.dart';

class CustomProvider extends ChangeNotifier {
  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }
}
```

### `core/presentation/manager/custom_state.dart`

```dart
enum ViewStatus { idle, loading, success, error }

class CustomState {
  final ViewStatus status;
  final String? errorMessage;

  const CustomState({
    this.status = ViewStatus.idle,
    this.errorMessage,
  });

  bool get isLoading => status == ViewStatus.loading;
  bool get hasError => status == ViewStatus.error;
}
```

Provider feature state classes extend `CustomState` and add `copyWith`.
Riverpod, Bloc, and Cubit generate manager-specific immutable state classes
instead of inheriting from this Provider base.

---

## 5. Naming conventions (contractual)

| Artifact            | Pattern                  | Example                          |
|---------------------|--------------------------|----------------------------------|
| Feature folder      | `snake_case`             | `add_new_menu`                   |
| Provider            | `<Feature>Provider`      | `OrdersProvider`                 |
| State               | `<Feature>State`         | `OrdersState`                    |
| Use case            | `<Verb><Noun>Usecase`    | `FetchOrdersUsecase`             |
| Repository (abstract) | `<Feature>Repository`  | `OrdersRepository`               |
| Repository impl     | `<Feature>RepositoryImpl`| `OrdersRepositoryImpl`           |
| API service         | `<Feature>ApiService`    | `OrdersApiService`               |
| DTO                 | `<Name>Dto`              | `OrderDto`                       |
| Payload (request)   | `<Name>Payload`          | `CreateOrderPayload`             |
| Domain model        | `<Name>`                 | `Order`                          |
| DI module           | `<Feature>Module`        | `OrdersModule`                   |
| Screen              | `<Name>Screen`           | `OrdersScreen` (static `id`)     |
| File names          | `snake_case.dart`        | `orders_provider.dart`           |

---

## 6. Services

A service is a cross-cutting singleton in `lib/services/`, registered in DI as a
`@lazySingleton` in Clean and MVVM projects or as one shared instance in the
Flutter Modular composition root.

ForgeKit supports three service categories:

- `generic` creates an initialized singleton skeleton for an application-owned
  SDK adapter or cross-cutting concern. The developer implements the
  service-specific behavior.
- `shared_preferences` and `flutter_secure_storage` create complete,
  driver-backed storage implementations.
- Firebase capabilities create complete, SDK-backed implementations through
  `forgekit add firebase` (see §6.1). **Unreleased** — implemented but not yet
  verified against a real Firebase project.

Names such as `analytics`, `app_review`, and `deep_link` currently use the
generic generator. ForgeKit does not install or implement their third-party
SDKs automatically.

Each generated service:
1. Creates `lib/services/<name>_service.dart` with an `init()` method.
2. Registers it in DI (`@lazySingleton` annotation + re-run build_runner).
3. Inserts an idempotent `init()` call after dependency configuration and
   before `runApp`.

Those integration guarantees apply to `forgekit add service`. Rendering the
underlying Mason brick directly creates its local scaffold but bypasses
ForgeKit's project-aware DI, bootstrap, and transaction orchestration.

Storage services are first-class driver-backed generators:

```sh
forgekit add service local_storage --driver shared_preferences
forgekit add service secure_storage --driver flutter_secure_storage
```

These commands add the package dependency, generate complete typed storage
functions, register the service in Injectable/GetIt or Flutter Modular, and
insert an idempotent `init()` call before `runApp`.

Storage security boundaries are contractual:

- SharedPreferences is for non-sensitive preferences and cache-like settings;
  the generated service uses `SharedPreferencesAsync` to avoid stale
  process-local caches. It is not a credential store and its writes are not a
  durable database guarantee.
- Secure storage is for revocable runtime material such as session and refresh
  tokens received after authentication. It does not make a static credential
  safe to compile or bundle into the application.
- Privileged API keys, signing keys, passwords, and backend credentials remain
  server-side. ForgeKit environment assets are public client configuration.

In an interactive terminal, omitting `--driver` asks the developer to choose
between the generic and storage implementations. In automation, pass the
driver explicitly. A generic service is fully registered and initialized, but
its application-specific `init()` body remains intentionally unfinished.

### 6.1 Firebase

> **Unreleased and untested.** `forgekit add firebase` is implemented but has
> not been verified against a real Firebase project. It is deliberately absent
> from the README until it has been. Treat this section as the intended contract
> rather than a description of shipped behaviour, and do not rely on it in a
> production project yet.

```sh
forgekit add firebase --features crashlytics,analytics,push,remote_config
```

Omitting `--features` in an interactive terminal presents a multi-select. In
automation the flag is required; the command refuses to prompt.

| Capability | Generates | Package |
| --- | --- | --- |
| `crashlytics` | `lib/services/crashlytics_service.dart` | `firebase_crashlytics: ^5.2.3` |
| `analytics` | `lib/services/analytics_service.dart` | `firebase_analytics: ^12.4.2` |
| `push` | `lib/services/push_notification_service.dart` | `firebase_messaging: ^16.2.0` |
| `remote_config` | `lib/services/remote_config_service.dart` | `firebase_remote_config: ^6.4.0` |
| `backend` | Not implemented yet; the value is accepted and rejected with an explanatory message rather than an allowed-values error | — |

Every capability adds `firebase_core: ^4.12.1`.

**Initialization order within the selection is fixed**, not argument order:
`crashlytics`, `analytics`, `push`, `remote_config`. Crashlytics is first so its
`FlutterError.onError` and `PlatformDispatcher.instance.onError` handlers are
installed before any later service can throw. Errors raised earlier than that —
inside `configureDependencies()`, for instance — are not captured.

**Division of responsibility.** ForgeKit generates application wiring only.
Firebase project registration, platform enablement, `lib/firebase_options.dart`,
`android/app/google-services.json`, and `ios/Runner/GoogleService-Info.plist`
belong to the FlutterFire CLI. `forgekit add firebase` **fails** when
`lib/firebase_options.dart` is absent rather than generating code that
references a class that does not exist, and directs the developer to
`flutterfire configure`.

**Initialization order is a contract.** `Firebase.initializeApp` is inserted
*before* `configureDependencies()`, not at the shared
`// forgekit:service-initializers` marker. `FirebaseMessaging.instance` and
`FirebaseRemoteConfig.instance` both throw when the core app is uninitialized,
so a `@lazySingleton` resolved during DI setup would construct too early. In
Modular projects, which have no GetIt bootstrap, initialization is inserted
directly after `WidgetsFlutterBinding.ensureInitialized()`.

The insertion is idempotent: re-running the command to add a second capability
does not duplicate the call.

**Generated services follow the standard §6 contract** — one file per
capability in `lib/services/`, `@lazySingleton` in Clean and MVVM, a shared
instance in the Modular composition root, an idempotent `init()`, and an
initializer call before `runApp`.

**Platform coverage is guarded, not assumed.** `create app` offers all six
Flutter platforms; no Firebase plugin implements all of them. Every generated
`init()` opens with a `defaultTargetPlatform` check and returns early on an
unsupported target, because `init()` is awaited before `runApp` and a
`MissingPluginException` there would abort startup rather than degrade.
Crashlytics additionally excludes web. On web `defaultTargetPlatform` reports
the browser's host platform, so `kIsWeb` is tested separately.

Five boundaries the generated code documents rather than solves:

- The FCM background handler is a top-level `@pragma('vm:entry-point')`
  function. It runs in a separate isolate with no access to the DI graph, so it
  cannot be a service method.
- Remote Config defaults are declared as a `static const Map` on the service. A
  key that exists in neither the defaults nor the server payload returns a zero
  value instead of throwing, so declaring every key locally is required.
- Crashlytics requires the `com.google.firebase.crashlytics` Gradle plugin in
  `android/app`. Without it Dart errors still report, so the dashboard looks
  healthy while native Android crashes and symbol upload silently do nothing.
  `forgekit doctor` warns when the dependency is present and the plugin is not.
- Analytics screen tracking is not automatic. `AnalyticsService` exposes a
  single `FirebaseAnalyticsObserver` that the application attaches to
  `MaterialApp.navigatorObservers` or `GoRouter.observers`. ForgeKit does not
  wire it, because the insertion point differs per router and per profile.

Platform work ForgeKit cannot perform is reported after generation: the
Crashlytics Gradle plugin, the analytics observer, iOS Push Notifications and
Background Modes capabilities, and the APNs key upload.

---

## 7. Routing

Clean and MVVM projects choose either GoRouter or named routes during app
creation. GoRouter is the interactive default; `--router named` and
`--router go_router` make the choice explicit for scripts and CI. A project
uses one central routing style consistently.

Each primary feature screen exposes `static const id = '/orders';`. Additional
Clean and MVVM screens use feature-qualified ids such as
`/orders/order_detail` to avoid cross-feature collisions. Modular screen ids
are module-relative child paths.

ForgeKit registers routes automatically:

- Named-route projects receive a screen import and entry in the central
  `MaterialApp.routes` map.
- GoRouter projects receive the feature route-list import and spread, or a
  direct `GoRoute` for an additional screen.
- Modular projects receive a child route in the generated feature module.

This automatic integration is performed by the `forgekit` command. Direct
Mason rendering bypasses project-aware route orchestration.

Generated insertions carry ForgeKit ownership markers and are idempotent. If
the configured insertion point cannot be found, generation fails and the
project transaction restores the previous state.

---

## 8. Dependency injection wiring

- `getIt` is the global `GetIt.instance`.
- `configureDependencies()` (in `core_module_container.dart`) calls `getIt.init()`.
- Each feature has a `@module` abstract class in `features/<feature>/di/<feature>_module.dart`
  that provides the retrofit `ApiService` and binds `RepositoryImpl` to `Repository`.
- Use cases and Provider, Bloc, or Cubit managers are annotated for Injectable
  so they are wired automatically. Riverpod notifiers are owned by Riverpod's
  generated provider declarations instead of GetIt.
- After any generation that touches DI, run: `dart run build_runner build`.
  The CLI/brick hooks do this for you (unless `--no-build-runner`).

---

## 9. Theme / design system

- Colors: `core/presentation/theme/colors/colors.dart` (const `Color` values).
- Typography: `core/presentation/theme/text_theme.dart` (`MyTextTheme` with light/dark).
- Theme assembly: `core/presentation/theme/app_theme.dart` (`AppTheme` mixin exposing
  `lightTheme()` / `darkTheme()` building `ThemeData` + Material 3 `ColorScheme`).
- Theme switching follows the selected state profile; Provider uses
  `ThemeProvider extends ChangeNotifier`.
- Shared widgets live in `core/presentation/widgets/` and are added via the `widget` brick.

---

## 10. Documented project choices

Two project-wide choices are supported without forking the generators:

1. **Routing** — `--router=go_router` (interactive default) or
   `--router=named` for Clean and MVVM; Flutter Modular owns routing in the
   Modular profile.
2. **State management** — Provider, Riverpod, Bloc, or Cubit.

Clean and MVVM retain the Injectable/GetIt composition model; Modular retains
Flutter Modular composition. Retrofit/JSON Serializable generation and the
top-level `lib/services/` location remain consistent across profiles.
