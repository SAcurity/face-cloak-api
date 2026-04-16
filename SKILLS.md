# Patterns & Skills: Database and ORM Migration

This document outlines the architectural patterns and engineering standards for migrating from a file-based store to a relational database using Sequel ORM, based on the `tyto2026-api-1-db-orm` reference implementation.

## 1. Architecture & Dependency Layer

### Core Stack
- **Web Framework:** Roda (Routing Tree)
- **ORM:** Sequel (Toolkit for SQL databases)
- **Database:** SQLite3 (`~>2.0`) for development/test, Postgres-ready for production.
- **Secrets Management:** Figaro (`config/secrets.yml` gitignored).

### Key Files
- `config/environments.rb`: Centralized configuration for Sequel connection and Figaro.
- `require_app.rb`: Custom autoloader for models and controllers.
- `config.ru`: Clean entry point using `require_app` and `freeze.app`.

## 2. Configuration & Security Hygiene

### Secret Protection
- **Rule:** Never leak secrets to child processes or dependent gems.
- **Pattern:** Use `ENV.delete('DATABASE_URL')` in `config/environments.rb` immediately after reading it into the Sequel connection.
- **Verification:** Implement a regression test (e.g., `spec/env_spec.rb`) asserting `Api.config.DATABASE_URL` is `nil`.

### Safe YAML Loading
- **Rule:** Prevent arbitrary code execution during seed/fixture loading.
- **Pattern:** Use `YAML.safe_load_file` instead of `YAML.load`.
- **Handling Scalars:** For `Time` or other non-standard classes, explicitly allow them:
  ```ruby
  YAML.safe_load_file(path, permitted_classes: [Time])
  ```

## 3. Database & Schema Layer

### Migrations
- Use Sequel's migration DSL in `db/migrations/`.
- Naming: `001_xxx_create.rb`, `002_yyy_create.rb`.
- **Integrity:** Use foreign keys with `null: false` where relationships are mandatory.
- **Performance:** Add unique constraints on logical keys (e.g., `unique [:course_id, :name]`).

### Models
- **Associations:** Use `one_to_many` and `many_to_one`.
- **Cascading Deletes:** Use `plugin :association_dependencies` to manage cleanup:
  ```ruby
  plugin :association_dependencies, events: :destroy
  ```
- **Timestamps:** Enable `plugin :timestamps`.
- **Serialization:** Implement `to_json` with a consistent envelope:
  ```ruby
  { data: { type: 'resource_name', attributes: { ... } } }
  ```

## 4. Controller Layer (Roda)

### Routing Patterns
- **Nested Resources:** Use Roda's tree to represent hierarchies (e.g., `/courses/[id]/events`).
- **Standard Headers:** Use `@api_root` and `@resource_route` variables to build `Location` headers for `201 Created` responses.
- **Error Handling:** Wrap database operations in `rescue StandardError` and use `routing.halt 4xx` with descriptive JSON messages.
- **ORM Best Practices:** Use `save_changes` instead of `save` to avoid unnecessary updates and keep `rubocop-sequel` happy.

## 5. Testing Strategy

### Environment Separation
- Hard-code `ENV['RACK_ENV'] = 'test'` as the first line in `spec_helper.rb`.

### Database Wiping
- Implement a `wipe_database` helper in `spec_helper.rb` to clear all tables before/after each test run.
- **Rule:** Do not rely on file-system `Dir.glob` wipes; use `app.DB[:table].delete`.

### HAPPY / SAD / BAD Convention
- **HAPPY:** Test successful creation, listing, and retrieval.
- **SAD:** Test "not found" (404) or "invalid input" (400) cases.
- **BAD:** (If applicable) Test unauthorized access or malformed requests.

## 6. Operations & Static Analysis

### Rake Tasks
- Provide a robust `Rakefile` with:
  - `db:migrate`, `db:drop` (with production guards), `db:seed`.
  - `spec` (default task).
  - `audit` (using `bundler-audit`).
  - `style` (using `rubocop`).
  - `release_check` (runs all checks before a merge).

### RuboCop Plugins
Enforce ORM and performance standards by including these gems:
- `rubocop-performance`
- `rubocop-rake`
- `rubocop-sequel`
