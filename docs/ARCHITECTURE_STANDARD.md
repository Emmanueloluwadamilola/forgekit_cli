# ForgeKit Flutter Architecture Standard

This document is the **single source of truth** for how ForgeKit Flutter apps are structured.
Every generator (Mason brick, `forgekit` CLI, VSCode extension) produces code that conforms to
this standard. It was distilled from a review of seven production apps: `pof_customer`,
`pof_vendor`, `runnars_mobile`, `my-cross-river-app`, `tantita_mobile`, `airwifi_mobile`,
and `the-lex-app-mobile`.

> If a generator and this document disagree, this document wins. Update the document first,
> then the generators.

---

## 1. Stack (locked)

| Concern            | Choice                                                              | Notes |
|--------------------|--------------------------------------------------------------------|-------|
| Architecture       | Clean Architecture, feature-first                                  | data / domain / presentation inside each feature |
| State management   | Provider, Riverpod, Bloc, or Cubit                                  | selected project-wide in `forgekit.yaml`; Provider uses the ForgeKit `CustomProvider` base and every option uses an immutable paired `*State` object |
| Dependency injection | `get_it` + `injectable`                                          | one `@module` per feature, generated container |
| Networking         | `dio` + `retrofit` + `awesome_dio_interceptor`                     | 401/token-refresh interceptor, `ApiResult<T>` wrapper |
| Serialization      | `json_serializable` + `json_annotation`                            | no `freezed`; explicit DTO → domain conversion |
| Routing            | Named routes + static `.id` on screens + navigation extension      | see §7; `go_router` is the documented modern alternative |
| Spacing            | `gap`                                                              | `Gap(16)` instead of `SizedBox` |
| Responsive         | `flutter_screenutil` (optional per project)                        | `designSize: Size(360, 690)` |

### Locked dependency versions (baseline)

```yaml
provider: ^6.1.2
flutter_riverpod: ^2.6.1 # when the Riverpod profile is selected
flutter_bloc: ^9.1.0     # when the Bloc or Cubit profile is selected
get_it: ^8.0.3
injectable: ^2.5.0
dio: ^5.8.0
retrofit: ^4.9.2
awesome_dio_interceptor: ^1.3.0
json_annotation: ^4.12.0
gap: ^3.0.1
flutter_secure_storage: ^9.2.2
dartz: ^0.10.1            # optional, for Either-style error handling

# dev
build_runner: ^2.4.13
injectable_generator: ^2.6.1
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
│   │   ├── core_module.dart                 # @module: Dio, SharedPreferences, SecureStorage
│   │   ├── core_module_container.dart        # getIt + configureDependencies()
│   │   └── core_module_container.config.dart # GENERATED
│   ├── domain/
│   │   ├── api/
│   │   │   └── api_result.dart               # ApiResult<T> sealed wrapper
│   │   └── usecase/
│   │       └── use_case.dart                 # UseCase<Type, Params> base
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
│       │   └── drawables.dart                # asset path constants
│       ├── utils/
│       │   ├── extensions/                   # navigation.dart, context_ext.dart, ...
│       │   └── validators.dart
│       └── widgets/                          # shared design-system widgets
│           ├── button.dart
│           ├── input_field.dart
│           ├── svg_image.dart
│           ├── cached_image.dart
│           ├── clickable.dart
│           ├── empty_states.dart
│           ├── shimmer_card.dart
│           ├── pop_widget.dart
│           └── provider_widget.dart
├── features/
│   └── <feature>/                            # see §3
├── services/                                 # cross-cutting singletons (see §6)
│   ├── notification_service.dart
│   ├── local_notification_service.dart
│   └── remote_config_service.dart
└── main.dart
```

**Decision locked:** services live in `lib/services/` (top-level), not `lib/core/services/`.
This resolves the inconsistency found across the reviewed apps.

---

## 3. Feature layout (the unit the `feature` brick generates)

For a feature named `orders` (snake_case folder, PascalCase classes):

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
abstract class UseCase<Type, Params> {
  Future<ApiResult<Type>> call(Params params);
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

Feature `*State` classes extend `CustomState` and add `copyWith`.

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

## 6. Services (the `service` brick)

A service is a cross-cutting singleton in `lib/services/`, registered in DI as a
`@lazySingleton` or via the core module. Standard services the generator supports:

- `notification_service` — Firebase Messaging
- `local_notification_service` — flutter_local_notifications
- `remote_config_service` — Firebase Remote Config / feature flags
- `secure_storage_service` — flutter_secure_storage wrapper
- `analytics_service` — analytics façade
- `app_review_service` — in-app review
- `deep_link_service` — link routing

Each generated service:
1. Creates `lib/services/<name>_service.dart` with an `init()` method.
2. Registers it in DI (`@lazySingleton` annotation + re-run build_runner).
3. Adds an `await getIt<XService>().init();` line to `main.dart` bootstrap (via hook).

---

## 7. Routing

**Default (locked):** named routes. Each screen exposes `static const id = '/orders';`
and is registered in `core/presentation/app/app.dart`'s `routes` map. A `navigation.dart`
extension provides `context.pushNamed(id)`, `context.pushAndClear(id)`, `context.pop()`.

The `feature` brick's post-gen hook inserts the route into the `routes` map automatically.

**Modern alternative (documented option):** `go_router`. If `--router=go_router` is passed,
the brick emits a `<feature>_routes.dart` with `GoRoute` entries and registers them in a
central `AppRouter`. Choose one per project and stay consistent.

---

## 8. Dependency injection wiring

- `getIt` is the global `GetIt.instance`.
- `configureDependencies()` (in `core_module_container.dart`) calls `getIt.init()`.
- Each feature has a `@module` abstract class in `features/<feature>/di/<feature>_module.dart`
  that provides the retrofit `ApiService` and binds `RepositoryImpl` to `Repository`.
- Use cases and providers are annotated `@injectable` / `@lazySingleton` so they are wired
  automatically.
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

1. **Routing** — `--router=named` (default) or `--router=go_router`.
2. **State management** — Provider, Riverpod, Bloc, or Cubit.

Dependency injection, networking, serialization, and the top-level `lib/services/`
location remain consistent across all profiles.
