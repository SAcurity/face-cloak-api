# GEMINI.md

This file provides guidance to Gemini CLI when working with code in this repository.

## Project Overview

`face-cloak-api` is the JSON Web API for FaceCloak, an application privacy controls for detected faces in images.

The repo follows a branch-by-branch progression where each numbered branch introduces new functionality and a new security concern. Branches are merged weekly into `main`.

- **Language/runtime:** Ruby 4.0.1
- **Framework:** Roda
- **ORM:** Sequel
- **Database:** SQLite for development/test, Postgres-ready for production.
- **Config/secrets:** Figaro (`config/secrets.yml`, gitignored)
- **Crypto:** RbNaCl (SecureDB)
- **Testing:** Minitest + minitest-rg + rack-test

## Commands

- **Install dependencies:** `bundle install`
- **Setup dev database:** `rake db:migrate`
- **Setup test database:** `RACK_ENV=test rake db:migrate`
- **Run server:** `puma`
- **Run tests:** `rake spec`
- **Lint:** `bundle exec rubocop .`
- **Audit dependencies:** `rake audit`
- **Full release check:** `rake release_check` (spec + style + audit)
- **Console:** `rake console`
- **Wipe database rows:** `rake db:delete`
- **Drop local db file:** `rake db:drop`
- **Rerun the server:** `rake rerun`

## Architecture

### Layout
```text
.
├── Gemfile / Gemfile.lock
├── Rakefile
├── require_app.rb          # autoloader for config / app/models / app/controllers
├── config.ru
├── config/
│   ├── environments.rb     # Figaro + Sequel connection + Secret Hygiene
│   ├── secrets.yml         # gitignored — real dev/test DB URLs and DB_KEY
│   └── secrets-example.yml # committed template
├── app/
│   ├── controllers/app.rb  # Roda routing tree
│   ├── lib/secure_db.rb    # RbNaCl encryption wrapper
│   └── models/             # Sequel::Model classes (Image, FaceRecord, ActionLog)
├── db/
│   ├── migrations/         # Sequel migrations (UUID optimized)
│   ├── seeds/              # YAML fixtures
│   └── local/              # SQLite files and Image Storage
└── spec/                   # Granular class-based tests
```

### Routing & API Reference

REST routes are versioned under `api/v1/...` with strict RBAC:

#### Root
- GET `/` : API metadata and resources list

#### Images
- GET `api/v1/images` : List all image metadata
- POST `api/v1/images` : Upload image (Multipart: `owner_id`, `file`). Triggers **Automated Face Detection**.
- GET `api/v1/images/[ID]` : Retrieve image binary. 
    - **Privacy-First Default**: Returns raw binary ONLY if ALL faces are `unveil`; otherwise filtered. (Applied to everyone, including Owner).
- GET `api/v1/images/[ID]/raw` : **Administrative Access**. 
    - **Owner ONLY**: ALWAYS returns raw binary. 
    - **Others**: Returns 403 Forbidden.
- DELETE `api/v1/images/[ID]` : Deletes image and associated data (Owner only).
- GET `api/v1/images/[ID]/logs` : Audit logs for all faces in this image.

#### Face Records
- GET `api/v1/face_records` : List all face records.
- GET `api/v1/face_records/[ID]` : Single record details.
- POST `api/v1/face_records` : Manual creation (Owner only).
- POST `api/v1/face_records/[ID]/assignment` : Assign face to a user (Owner only).
- DELETE `api/v1/face_records/[ID]/assignment` : Clear assignment (Owner only).
- POST `api/v1/face_records/[ID]/respond` : Set mask/unveil preference. 
    - **Zero-Trust Rule**: ONLY the `assigned_user_id` can call this.
- GET `api/v1/face_records/[ID]/logs` : Audit logs for a specific face.

### Data Standards
- **Identifiers**: All Primary and Foreign keys (`id`, `image_id`, `face_record_id`) use **UUID v4** strings for security and PostgreSQL parity. `action_logs.id` uses Integer for ordering.
- **Envelope**: Standard JSON API envelope `{ data: { type: "...", attributes: { ... } } }`.

### Security Conventions (Hardening)

#### 1. Zero-Trust Privacy
- **Direct Access Prohibition**: NEVER return raw image data if faces are unassigned or masked.
- **Permission Isolation**: Owner can manage distribution (Assign), but ONLY Assignee can authorize data viewing (Unveil).

#### 2. Data Protection (PII)
- **Encryption**: User identifiers (`owner_id`, `assigned_user_id`, `actor_id`) MUST be encrypted at rest using `SecureDB` (RbNaCl).
- **Secret Hygiene**: Sensitive env vars (`DATABASE_URL`, `DB_KEY`) MUST be deleted from `ENV` immediately after usage in `environments.rb`.

#### 3. Database Integrity
- **Migrations**: Use explicit `uuid` types or `String :id, primary_key: true` to avoid SQLite integer mapping conflicts.
- **SQL Injection**: All queries MUST use Sequel's parameterized DSL.
- **Mass Assignment**: Models MUST use `whitelist_security` to restrict allowed columns.

#### 4. Audit & Traceability
- Every state-changing action (create, assign, unassign, respond) MUST generate an `ActionLog` entry.
- Centralized Error Handler: Classified logging (WARN for 400s, ERROR for 500s) without leaking stack traces to clients.

## Style & Verification
- RuboCop: Follow idiomatic Ruby. Targets version 4.0. No offenses allowed.
- Tests: Every security rule must have a verified "Sad Path" test case.
- `rake release_check`: Mandatory green status before merging to main.
