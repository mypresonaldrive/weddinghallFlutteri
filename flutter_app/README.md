# Gatherhall Flutter app

Cross-platform client for the Gatherhall marriage-hall SaaS:

| Target | Status |
| --- | --- |
| Android (APK) | built in CI (`.github/workflows/flutter-ci.yml`) |
| iOS (no codesign) | built on demand (`workflow_dispatch` + `build_ios`) |
| Windows desktop | built in CI |
| Web | not targeted (native desktop + mobile first) |

## Design constraints

- **Zero third-party packages.** Only `flutter` + `flutter_test`. All HTTP is
  `dart:io` `HttpClient` with a hand-rolled cookie jar and CSRF double-submit
  (`gh_csrf` cookie echoed as `x-csrf-token`), JSON via `dart:convert`,
  persistence via a tiny JSON file store.
- **Ports of the shared business logic**, kept line-faithful to
  `shared/*.js` so quotes match the server: `core/duration.dart`
  (booking windows), `core/pricing.dart` (quote preview), plus the validation
  rules in `core/constants.dart`.
- **Same API contract as the web app**: whole-record `PUT` (the server
  replaces the stored body), entitlement gates (402 → banner), MFA gates
  (403 → authenticator prompt), demo + SaaS mode differences handled at
  runtime through `/api/config` and `me()`.

## Layout

```
lib/main.dart            bootstrap: KeyValueStore → Session/Appearance/Workspace
lib/src/app.dart         boot gate (splash / unreachable / auth / onboarding / shell)
lib/src/core/            paths, storage, api, session, store, duration, pricing,
                         constants, models, formatters, appearance, csv
lib/src/widgets/common.dart   shared UI (PageScaffold, StatusChip, editors…)
lib/src/screens/         auth, shell, dashboard, halls, clients, staff, bookings,
                         booking_wizard (4-step), calendar, catalog (plans/addons),
                         payments, reports, settings (+ MFA), billing,
                         platform_console (metrics, orgs, plans, CMS, integrations)
tool/e2e_demo.dart       E2E smoke test against the demo server
test/                    unit + widget tests (pure logic, api client, widgets)
```

## Running locally

Requires the Flutter stable SDK (CI uses `subosito/flutter-action@v2`,
channel `stable`) and Node ≥ 22.13 for the backend.

```bash
# terminal 1 – demo backend (defaults to demo mode outside production)
node server.js

# terminal 2
cd flutter_app
flutter pub get
flutter run -d windows   # or chrome / <android-device-id> / ios
```

Desktop platforms need their generated scaffolds (`android/`, `ios/`,
`windows/`); on this branch the first CI run's `bootstrap-scaffold` job runs
`flutter create` in CI and commits the result back automatically (sandbox
artifact downloads are blocked, and `workflow_dispatch` only works from the
default branch).

## Tests & CI

```bash
flutter analyze --no-fatal-infos
flutter test
dart run tool/e2e_demo.dart   # with the demo server running on :3000
```

CI (`.github/workflows/flutter-ci.yml`) runs analyze + tests on every push,
then the E2E suite against a booted demo server, then builds the Android APK
and the Windows release. iOS builds run only when dispatched with `build_ios`.

## Branch note

Session work is fixed to the branch `arena/01a0f024-weddinghallflutteri`
(Arena ties the session to it), so all Flutter development, commits and pushes
happen there.
