# Implementation Plan: Katalog Bidan dan Ketersediaan Slot

**Date**: 2026-11-04 | **Spec**: [PRD_TeleBunda_AI_MVP.md](../../../PRD_TeleBunda_AI_MVP.md), FR-05 and the relevant catalog states from FR-14

## Summary

Implement the FR-05 patient-facing midwife catalog and available-slot lookup using Laravel as the trusted API boundary and Firestore as the source of truth. Only active, verified midwives and future, valid, available 30-minute slots will be returned. Flutter will consume backend data only; frontend-only midwife and slot fixtures are removed and never used as a fallback.

The current PRD does not define public midwife pricing, ratings, review counts, experience years, STR numbers, or clinic affiliations in the `midwives/{uid}` collection. These values must not be fabricated or exposed from another collection. Live-provider booking remains unavailable until the FR-06 atomic booking/hold endpoint and the price contract are defined and implemented.

## Technical Context

**Language/Version**: PHP 8.3 / Laravel 13; Dart / Flutter  
**Primary Dependencies**: Laravel HTTP client, Firebase ID-token verification, Flutter Riverpod, Dio  
**Storage**: Firestore REST API; no SQL persistence introduced  
**Testing**: Laravel feature tests with mocked `FirebaseService`; Flutter tests for JSON parsing, provider states, and existing demo behavior  
**Target Platform**: Laravel REST API and Flutter Android application  
**Performance Goals**: Bounded Firestore queries and API timeouts; no client-side Firestore access for catalog or slot writes  
**Constraints**: Follow PRD role/status authority; never trust client-provided role or verification state; do not use frontend-only catalog fixtures or fabricated profile defaults; use UTC timestamps and display using the app's existing local-time formatters.

### Scope

- In scope: FR-05 and the catalog/slot loading, empty, and network-error states within FR-14.
- Out of scope: booking holds (FR-06), pricing/payment (FR-07/08), midwife administration/verification, and unrelated MVP features.
- Operational prerequisite: a trusted administrator or other trusted process must create eligible `midwives/{uid}` and `slots/{slotId}` documents. The endpoint must return an empty list when no eligible records exist; it must not seed or approve records itself.

## Constitution Check

No separate `constitution.md` was found. The plan follows the governing PRD and backend project rules:

| Principle | Result | Evidence |
|---|---|---|
| Backend owns authorization and eligibility decisions | PASS | Patient role is read from `users/{uid}`; active/verified and slot status are filtered by Laravel/Firestore queries. |
| Client cannot set trusted status or availability | PASS | This scope adds read-only endpoints only. |
| Firestore remains the source of truth; no SQL database is added | PASS | Reads use the existing `FirebaseService` and Firestore REST API. |
| Catalog data comes from the backend only | PASS | Midwife and slot fixtures are removed; missing optional fields remain absent rather than receiving sample values. |
| Keep the change scoped to the requested feature | PASS | Booking creation, payment, and midwife approval flows are deferred. |

## Applied Guidelines

- `backend/AGENTS.md` and `backend/.agents/skills/laravel-best-practices/rules/security.md`: enforce authorization independently of authentication, avoid trusting request fields, and keep secrets in configuration.
- `backend/.agents/skills/laravel-best-practices/rules/http-client.md`: configure explicit timeouts, call `throw()` for unexpected Firestore responses, and fake external requests in tests.
- `backend/.agents/skills/laravel-best-practices/rules/routing.md` and `validation.md`: keep controllers focused and follow existing explicit API route conventions.
- No matching migration-specific guidelines or project topology artifact were found.

## Implementation Steps

### Phase 1: Foundational

#### 1.1 Enforce patient access and define trusted Firestore reads
- **Requirements**: FR-05
- **Design inputs**: PRD sections 7–9; `backend/app/Http/Middleware/VerifyFirebaseIdToken.php`; `backend/app/Services/FirebaseService.php`
- **Description**: Add patient-role authorization based on the Firestore user profile. Extend the existing Firebase service with allowlisted reads for active, verified midwives and available slots. Keep query inputs constrained to the authenticated request and the requested midwife ID. Filter out invalid, expired, wrong-duration, or mismatched slot records; report malformed persisted records without exposing profile data.

### Phase 2: User Story 1 — Browse verified midwives and available slots (Priority: P1)

**Goal**: An authenticated patient can browse only eligible midwives and current available slots.

**Independent Test**: With a patient profile and eligible Firestore fixtures, the API returns only eligible catalog entries and future valid slots. A missing Firebase ID token returns 401, a non-patient profile returns 403, and no eligible records returns an empty `data` array.

#### 2.1 Expose the catalog and slot API
- **Requirements**: FR-05
- **Design inputs**: PRD section 9 (`GET /api/midwives`, `GET /api/midwives/{id}/slots`)
- **Description**: Add read-only API routes and a focused controller. Return a stable `data` response envelope and only allowlisted public fields from the PRD; do not expose STR data from `users/{uid}` or internal hold fields.

#### 2.2 Connect Flutter models and repository to the API
- **Requirements**: FR-05
- **Design inputs**: `lib/data/models/midwife_model.dart`, `lib/data/models/slot_model.dart`, `lib/data/repositories/midwife_repository.dart`, `lib/core/network/api_client.dart`
- **Description**: Make fields absent from the PRD/API contract optional rather than supplying demo defaults. Remove frontend-only midwife and generated slot fixtures; fetch catalog and slot data only through the authenticated backend API, with no local fallback.

#### 2.3 Render catalog and slot states without misleading live data
- **Requirements**: FR-05; FR-14 (catalog/slot loading, empty, and network failure states only)
- **Design inputs**: `lib/features/midwife_catalog/screens/midwife_catalog_screen.dart`, `lib/features/midwife_catalog/screens/midwife_detail_screen.dart`, `lib/features/booking/screens/booking_form_screen.dart`
- **Description**: Integrate asynchronous data and clear loading, empty, retry, and error states. Hide values absent from the live API contract. Do not send live catalog selections into the current in-memory booking/checkout flow; keep live booking disabled until the separate FR-06 implementation is available.

#### 2.4 Verify API and Flutter behavior
- **Requirements**: FR-05; FR-14 (catalog/slot states)
- **Design inputs**: Existing Laravel and Flutter test suites
- **Description**: Add focused tests for authorization, response allowlists, eligible midwife filtering, valid slot filtering, JSON parsing without fabricated defaults, and demo-mode compatibility. Run Laravel tests, Flutter tests, `flutter analyze`, and the Android debug build.

## Project Structure

```text
backend/
  app/Http/Controllers/Api/MidwifeController.php
  app/Http/Middleware/RequirePatientRole.php
  app/Services/FirebaseService.php
  routes/api.php
  tests/Feature/MidwifeCatalogEndpointTest.php
lib/
  data/models/midwife_model.dart
  data/models/slot_model.dart
  data/repositories/auth_repository.dart
  data/repositories/midwife_repository.dart
  features/midwife_catalog/screens/midwife_catalog_screen.dart
  features/midwife_catalog/screens/midwife_detail_screen.dart
  features/booking/screens/booking_form_screen.dart
```

## Testing Strategy

- **appType**: Mixed REST API and Flutter Android application.
- **Critical user journeys**:
  1. Authenticated patient opens catalog and sees only active, verified midwives.
  2. Patient sees an empty state when Firestore contains no eligible midwives.
  3. Patient opens a provider and sees only future, available, valid 30-minute slots.
  4. Missing/expired authentication and non-patient roles are rejected.
  5. Catalog and slot data are never synthesized in Flutter; absent fields remain absent.
- **primaryValidationStack**: Laravel feature tests with mocked Firebase service; Flutter unit/widget tests; `flutter analyze`; Android debug build.
- **Environment requirements**: PHP/Composer dependencies and Flutter SDK; no live Firebase credentials needed for automated tests.
- **knownGaps**: Runtime verification against real Firestore requires seeded, trusted midwife and slot documents. Booking and payment cannot be validated in this plan because FR-06/07 are out of scope.
- **Test data strategy**: Use isolated mocked Firebase profiles and Firestore responses; do not write test records to the configured project. Flutter tests assert that the catalog has no local fixtures.
- **Acceptance criteria**: All automated checks pass; API eligibility and role rules match the PRD; live UI does not invent profile or pricing data; empty/error/loading states are visible and recoverable.
- **Validation review expectations**: Confirm no unauthorized role can query the catalog, no unapproved/inactive profile is returned, and no stale or malformed slot is presented as available.

## Requirement Mapping

| REQ ID | Description | Plan Items | Implementation Evidence |
|--------|-------------|------------|------------------------|
| FR-05 | Daftar bidan dan jadwal hanya menampilkan slot valid yang tersedia | 1.1, 2.1, 2.2, 2.3, 2.4 | `backend/app/Http/Middleware/RequirePatientRole.php`, `backend/app/Services/FirebaseService.php`, `backend/app/Http/Controllers/Api/MidwifeController.php`, `backend/tests/Feature/MidwifeCatalogEndpointTest.php`, Flutter model/repository/screens |
| FR-14 (partial) | Loading, kosong, dan gagal jaringan memiliki state UI jelas untuk katalog dan slot | 2.3, 2.4 | `lib/features/midwife_catalog/screens/midwife_catalog_screen.dart`, `lib/features/midwife_catalog/screens/midwife_detail_screen.dart`, `lib/features/booking/screens/booking_form_screen.dart` |

Requirements outside the stated FR-05 feature slice are intentionally not mapped by this plan; they remain for later implementation plans.

## Task Breakdown

### Phase 1: Foundational

- [x] T001 [Plan:1.1] Add patient-role middleware based on the trusted `users/{uid}` profile in `backend/app/Http/Middleware/RequirePatientRole.php`.
- [x] T002 [Plan:1.1] Add allowlisted Firestore queries for active verified midwives and available future 30-minute slots; log malformed records without profile data in `backend/app/Services/FirebaseService.php`.

### Phase 2: User Story 1 — Browse verified midwives and available slots

- [x] T003 [US1] [Plan:2.1] Add `GET /api/midwives` and `GET /api/midwives/{id}/slots` with patient authorization and public response allowlists in `backend/app/Http/Controllers/Api/MidwifeController.php` and `backend/routes/api.php`.
- [x] T004 [US1] [Plan:2.1,2.4] Add feature coverage for role enforcement, verified/active catalog filtering, slot eligibility, empty data, and non-disclosure of internal fields in `backend/tests/Feature/MidwifeCatalogEndpointTest.php`.
- [x] T005 [US1] [Plan:2.2] Update live JSON decoding so absent rating, price, STR, experience, and affiliation remain absent rather than receiving demo defaults in `lib/data/models/midwife_model.dart` and `lib/data/models/slot_model.dart`.
- [x] T006 [US1] [Plan:2.2] Implement authenticated API-backed catalog/detail/slot providers with no local fallback in `lib/data/repositories/midwife_repository.dart`.
- [x] T007 [US1] [Plan:2.3] Update catalog, detail, and booking screens for loading/empty/error/retry states; hide unavailable live fields and prevent live users from entering the in-memory booking flow in `lib/features/midwife_catalog/screens/midwife_catalog_screen.dart`, `lib/features/midwife_catalog/screens/midwife_detail_screen.dart`, and `lib/features/booking/screens/booking_form_screen.dart`.
- [x] T008 [US1] [Plan:2.4] Add focused Flutter tests for response parsing, missing optional values, async UI states, and demo fixtures; run Flutter analysis and Android debug build.
- [x] T009 [US1] [Plan:2.2,2.4] Remove frontend-only midwife and generated slot fixtures and assert optional API fields are not fabricated in `lib/data/repositories/midwife_repository.dart`, `lib/data/models/midwife_model.dart`, and `test/midwife_catalog_data_test.dart`.
