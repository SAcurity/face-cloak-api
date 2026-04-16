# Plan: Database and ORM Migration (face-cloak-api)

> **IMPORTANT**: This plan must be kept up-to-date at all times. It is the single source of truth for the migration from a file-based store to a relational database using Sequel ORM.

## Goal

Replace the ad-hoc file store with a real relational database (SQLite for development/testing, Postgres-ready for production). Introduce a structured schema with three entities, robust audit logging, secure public image viewing, and role-based access control (RBAC).

## Strategy: Vertical Slice

Deliver a complete, testable migration end-to-end:

1.  **Dependency + Config Layer** — Add Sequel, SQLite3, Figaro, and setup `config/environments.rb`.
2.  **Infrastructure Layer** — Implement `require_app.rb` autoloader and update `config.ru`.
3.  **Schema Layer** — Create migrations for `images`, `face_records`, and `action_logs` in `db/migrations/`.
4.  **Model Layer** — Implement `Image`, `FaceRecord`, and `ActionLog` as `Sequel::Model`. Use independent modules for types (`CloakType`, `ActionType`).
5.  **Controller Layer** — Refactor `app/controllers/app.rb` to use the ORM, follow RESTful patterns, and enforce RBAC.
6.  **Ops Layer** — Add a `Rakefile` for database management, testing, and linting. Enable Hirb in `.pryrc`.
7.  **Verify** — Ensure all specs pass, including public image viewing and restricted edits.

## Current State

- [x] Dependencies updated in `Gemfile` (Sequel, SQLite3, Figaro, Hirb, etc.)
- [x] Figaro + Sequel wired in `config/environments.rb` (with secret hygiene)
- [x] `require_app.rb` and `config.ru` updated for model-driven boot
- [x] Migrations for `images`, `face_records`, and `action_logs` in `db/migrations/`
- [x] `Image`, `FaceRecord`, and `ActionLog` models migrated to `Sequel::Model`
- [x] Independent `CloakType` and `ActionType` modules implemented
- [x] Local binary storage implemented (`db/local/storage/`) with generated storage keys
- [x] Public image viewing (`GET /images/:id` returns binary) implemented
- [x] RBAC: Only owner can create/assign face records
- [x] RBAC: Only assigned user can respond to face records
- [x] Automated traceable audit logging (`actor_id`) in controller
- [x] Controller refactored for DRY (helper methods for parsing and errors)
- [x] `Rakefile` implemented with `db:*` tasks and `release_check`
- [x] Hirb enabled in `.pryrc` for tabular console views
- [x] Complete, strictly schema-aligned seed files in `db/seeds/`
- [x] Specs updated and passing (18 tests covering RBAC and file storage)
- [x] RuboCop and security audit clean

## Domain Scope

- `Image`
    - `id`: Integer (Primary Key)
    - `owner_id`: String (Required)
    - `file_name`: String (Required, Unique)
    - `file_data`: Text (Required; generated local storage key)
    - `created_at`: DateTime
    - `updated_at`: DateTime
- `FaceRecord`
    - `id`: Integer (Primary Key)
    - `image_id`: Integer (Foreign Key to Images, Required)
    - `assigned_user_id`: String (Nullable)
    - `assigned_at`: DateTime (Nullable)
    - `responded_at`: DateTime (Nullable)
    - `cloak_type`: String (Default: 'blur' via `CloakType`)
    - `updated_at`: DateTime
    - `created_at`: DateTime
- `ActionLog`
    - `id`: Integer (Primary Key)
    - `face_record_id`: Integer (Foreign Key to FaceRecords, Required)
    - `actor_id`: String (Required; records who performed the action)
    - `action`: String (Required; limited via `ActionType`)
    - `created_at`: DateTime

## Security Requirements

1.  **Secret Hygiene:** `DATABASE_URL` deleted from `ENV` after connection. Verified by `spec/env_spec.rb`.
2.  **Public Viewing:** `GET /api/v1/images/:id` is public binary stream.
3.  **RBAC:** Creation/Assignment restricted to image owner via `X-Actor-Id` verification.
4.  **RBAC:** Responses restricted to `assigned_user_id`.
5.  **Obfuscation:** Files stored with random hashes to prevent guessable paths (IDOR protection).
6.  **Safe YAML:** Strict use of `YAML.safe_load_file` for seeding.

## Tasks

### 1. Setup & Dependencies
- [x] Update `Gemfile` with `sequel`, `figaro`, `sqlite3`, `rake`, `hirb`.
- [x] Update `.rubocop.yml` with performance and Sequel plugins.
- [x] Update `.gitignore` to include `db/local/*.db` and `db/local/storage/*`.

### 2. Configuration
- [x] Create `config/environments.rb` and `config/secrets-example.yml`.
- [x] Implement `require_app.rb` for automated autoloading.
- [x] Update `config.ru` to freeze and run the app.

### 3. Schema & Models
- [x] Implement migrations in `db/migrations/` (001-003).
- [x] Create `Image`, `FaceRecord`, and `ActionLog` models with full associations.
- [x] Implement `CloakType` and `ActionType` as independent logic modules.
- [x] Standardize JSON API envelopes via `to_h` and `to_json` overrides.

### 4. Controller & Ops
- [x] Refactor `app/controllers/app.rb` with DRY helper methods.
- [x] Implement public image serving and Base64 upload handling.
- [x] Implement RBAC guards for ownership and assignment.
- [x] Create `Rakefile` for migration, testing, and linting.
- [x] Enable Hirb in `.pryrc`.

### 5. Verification
- [x] Update `spec/spec_helper.rb` with `wipe_database` (including storage directory).
- [x] Refactor `spec/app_spec.rb` with 18 tests for new RBAC and routing patterns.
- [x] Verify `rake release_check` is completely green.

---
Last updated: 2026-04-13
