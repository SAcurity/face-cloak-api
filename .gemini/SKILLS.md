# Patterns & Skills: Database and ORM Migration

This document outlines the architectural patterns and engineering standards for migrating from a file-based store to a relational database using Sequel ORM, and hardening it for production security.

## 1. Architecture & Dependency Layer

### Core Stack
- **Web Framework:** Roda (Routing Tree)
- **ORM:** Sequel (Toolkit for SQL databases)
- **Database:** SQLite3 for development/test, Postgres-ready for production.
- **Secrets Management:** Figaro (`config/secrets.yml` gitignored).
- **Hardening:** `rbnacl` for encryption, `whitelist_security` for mass-assignment protection.

### Key Files
- `config/environments.rb`: Centralized configuration for Sequel connection, Figaro, and SecureDB setup.
- `app/lib/secure_db.rb`: Encryption/Decryption utility using `RbNaCl`.
- `require_app.rb`: Custom autoloader for models, controllers, and libraries.

## 2. Configuration & Security Hygiene

### Secret Protection
- **Rule:** Never leak secrets to child processes or dependent gems.
- **Pattern:** Use `ENV.delete('DATABASE_URL')` and `ENV.delete('DB_KEY')` in `config/environments.rb` immediately after loading.
- **Verification:** Implement a regression test asserting `DATABASE_URL` and `DB_KEY` are `nil` in `ENV`.

### Database Encryption (Database Hardening)
- **Pattern:** Use a `SecureDB` helper class to manage `RbNaCl::SimpleBox` operations.
- **Setup:** Call `SecureDB.setup(ENV.delete('DB_KEY'))` during initialization.

## 3. Database & Schema Layer

### ID Management & Standard Identifiers (Tyto API Alignment)
- **Standard:** Use **UUID v4** (128-bit) for all primary and foreign keys.
- **Rationale (Security):** Prevents Resource Enumeration attacks; high entropy ensures global uniqueness without collisions.
- **Rationale (Performance):** Aligns with PostgreSQL's native `UUID` type, which is faster and smaller for indexing than text-based custom IDs.
- **Implementation Pattern:** 
    - Enable `plugin :uuid` in models.
    - Use `unrestrict_primary_key` to allow manual assignment.
    - Generate IDs in a `before_create` hook: `self.id ||= SecureRandom.uuid`.
    - migrations use `String :id, primary_key: true` (SQLite) or native `uuid` type (Postgres).

### Migrations
- Use Sequel's migration DSL in `db/migrations/`.
- **Encryption Prefix:** Rename sensitive columns to include `_secure` suffix (e.g., `email_secure`).
- **Integrity:** Use foreign keys with `null: false` where relationships are mandatory.

### Models & Mass Assignment
- **Plugin:** Use `plugin :whitelist_security` in all Sequel models.
- **Allowed Columns:** Explicitly define `set_allowed_columns :col1, :col2` to prevent mass-assignment vulnerabilities.

### Secure Model Fields
- **Getters/Setters:** Override attribute methods to handle transparent encryption:
  ```ruby
  def field
    SecureDB.decrypt(field_secure)
  end

  def field=(plaintext)
    self.field_secure = SecureDB.encrypt(plaintext)
  end
  ```

## 4. Controller Layer (Roda)

### Error Handling & Logging
- **Mass Assignment:** Specifically rescue `Sequel::MassAssignmentRestriction` and return `400 Bad Request`.
- **Unknown Errors:** Rescue `StandardError` at the route or application level, log the error, and return `500 Internal Server Error` (do not leak stack traces).
- **Logging:** Use a centralized `Api.logger` (e.g., `Logger.new($stderr)`) to log security warnings and errors.

## 5. Testing Strategy

### Hardening Verification
- **Mass Assignment Test:** Attempt to update a restricted column and assert a `400` status.
- **SQL Injection Test:** Pass malicious strings into query parameters and verify they are handled as literal strings.
- **Encryption Test:** Verify that the database stores ciphertext while the model provides plaintext.

## 6. Operations & Static Analysis

### Rake Tasks
- **Key Generation:** Provide `rake db:gen_key` to generate a base64 encoded `DB_KEY`.
- **Audit:** Continue using `bundler-audit` and `rubocop-sequel`.
