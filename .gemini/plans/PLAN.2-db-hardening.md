# 2-db-hardening — Database Hardening

## Goal
Advance the database security of `face-cloak-api` by preventing mass assignment, ensuring SQL injection resistance, introducing column encryption for sensitive data, and enhancing error logging.

## Tasks

### 0. Maintenance & Updates
- [x] Update Ruby version (if needed) and all gems to their latest stable versions.
- [x] Run `bundle install` and verify existing tests pass.

### 1. Mass Assignment Protection
- [x] Enable `plugin :whitelist_security` for all models (`Image`, `FaceRecord`, `ActionLog`).
- [x] Define `set_allowed_columns` for each model to strictly control writable attributes.
- [x] Update `app/controllers/app.rb` to rescue `Sequel::MassAssignmentRestriction` and return `400 Bad Request`.
- [x] Add specs to verify that attempting to set restricted columns fails as expected.

### 2. SQL Injection Resistance
- [x] Review all model and controller code to ensure only Sequel's parameterized query methods are used.
- [x] Add specs to verify that malicious strings in query parameters are treated as literal values.

### 3. Column Encryption (Sensitive Data)
- [x] Identify sensitive columns:
    - `Image`: `owner_id` (PII)
    - `FaceRecord`: `assigned_user_id` (PII)
    - `ActionLog`: `actor_id` (PII)
- [x] Create `app/lib/secure_db.rb` for `RbNaCl` encryption.
- [x] Create migration to rename sensitive columns to `*_secure` (e.g., `owner_id_secure`).
- [x] Implement getter/setter overrides in models to handle transparent encryption.
- [x] Update `config/environments.rb` to setup `SecureDB` with a `DB_KEY`.
- [x] Add `DB_KEY` to `config/secrets.yml` and `config/secrets-example.yml`.
- [x] Add specs to verify that data is encrypted in the DB but readable as plaintext in the model.

### 4. Robust Logging & Error Handling
- [x] Setup `Api.logger` using Ruby's `Logger` class in `config/environments.rb`.
- [x] Implement global error handling in `app/controllers/app.rb` to rescue `StandardError`, log the incident, and return a generic `500` error to clients.
- [x] Log `Api.logger.warn` for mass assignment attempts and `Api.logger.error` for system failures.

### 5. UUID Migration & Standardization (Tyto-API Alignment)
- [x] Migrate all Primary and Foreign keys to standard **UUID v4** strings.
- [x] Update migrations to use `uuid :id, primary_key: true` and `foreign_key ..., type: :uuid`.
- [x] Remove obsolete `IdGenerator` and enable `unrestrict_primary_key` in models.
- [x] Verify PostgreSQL optimization readiness.

### 6. Zero-Trust Permission Architecture
- [x] **Automated Detection**: Implement `after_create` hook in `Image` model to automatically generate face records and audit logs on upload.
- [x] **Privacy-First Rendering**:
    - `GET /images/:id`: Returns filtered data by default to EVERYONE (including Owner) if any faces are masked.
    - `GET /images/:id/raw`: Administrative access strictly reserved for Owner to see raw binary.
- [x] **Strict Respond RBAC**: ONLY the `assigned_user_id` can unveil a face. Image owner is forbidden from unveiling records they are not assigned to.
- [x] **Anti-Abuse Constraint**: Limit Owner to only ONE self-assigned face record per image.

---
Last updated: 2026-04-23
