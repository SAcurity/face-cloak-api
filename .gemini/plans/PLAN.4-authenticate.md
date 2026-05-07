# 4-authenticate — Auth route, multi-route controllers, HttpRequest helper [COMPLETED]

## Goal
Implement a dedicated authentication route, modularize the API into multiple controllers using the `multi_route` plugin, and introduce an `HttpRequest` helper to centralize security enforcement and request parsing.

## Strategy
1. **HttpRequest Utility**: Extract request-level logic (TLS verification and JSON parsing) into a shared `HttpRequest` helper class.
2. **Modular Controllers**: Split the monolithic `app/controllers/app.rb` into specialized controller files (`accounts.rb`, `images.rb`, `face_records.rb`, `auth.rb`) using the `multi_route` plugin.
3. **Dedicated Authentication**: Move authentication logic to its own endpoint (`POST /api/v1/auth/authenticate`) and refine the `AuthenticateAccount` service to match the `tyto-api` pattern.
4. **JSON Envelope Normalization**: Standardize the API's JSON output to a consistent `{type, attributes, [include]}` structure across all models.
5. **Security Hardening**: Enforce SSL/TLS requirement across all API routes using environment-specific configuration (`SECURE_SCHEME`).

## Tasks

### Setup & Configuration
- [x] Add `SECURE_SCHEME` to `config/secrets-example.yml` and `config/secrets.yml` (HTTP for dev/test, HTTPS for production).
- [x] Update `Gemfile` to organize gems into logical development/test groups.

### Request Layer
- [x] Create `app/controllers/http_request.rb` to handle `secure?` checks and `body_data` parsing.
- [x] Update `app/controllers/app.rb` to use `plugin :multi_route` and enforce the security scheme globally.

### Controller Refactoring
- [x] **Auth Controller**: Create `app/controllers/auth.rb` with `POST /api/v1/auth/authenticate`.
- [x] **Accounts Controller**: Extract account-related routes to `app/controllers/accounts.rb`.
- [x] **Images Controller**: Extract image-related routes to `app/controllers/images.rb`.
- [x] **Face Records Controller**: Extract face record routes to `app/controllers/face_records.rb`.

### Service & Model Updates
- [x] Refine `AuthenticateAccount` service to include username in `UnauthorizedError` and adopt generic 403 error reporting.
- [x] Normalize `to_json` methods in `Account`, `Image`, `FaceRecord`, and `ActionLog` models to `{type, attributes, include}`.

### Testing & Verification
- [x] Add `spec/integration/api_auth_spec.rb` for authentication testing.
- [x] Update existing integration specs to reflect the new JSON envelope structure.
- [x] Run 100% of specs and perform `rake release_check`.

## Key Patterns from Tyto-API
- **HttpRequest helper**: Encapsulates `routing.scheme` and `routing.body.read`.
- **Multi-route**: Uses `routing.multi_route` to delegate to named route blocks.
- **UnauthorizedError**: Generic error message for clients, specific logging for server.
- **Consistent Envelopes**: Every resource returned follows the `{type, attributes}` pattern.
