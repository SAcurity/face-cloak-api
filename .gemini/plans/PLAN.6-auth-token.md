# 6-auth-token - Token-based Registration and Authorization [COMPLETED]

## Goal
Implement this week's token-based authorization milestone for the FaceCloak API by following the Tyto `6-auth-token` API reference. The API should issue encrypted auth tokens after login, require Bearer tokens for account-scoped routes, derive the requesting account from the token instead of request parameters or `X-Actor-Id`, and prepare the API side of email-verification registration.

## Source Requirements
Primary requirement document:

- `../6-auth-token/SEC Project - 009 Token-based Authorization.docx.pdf`

Reference implementation:

- `../6-auth-token/tyto2026-api-6-auth-token`

Key requirements from the PDF:

- Create a registration workflow that verifies user registration using a token.
- Use token payloads to avoid trusting temporary DB rows or caller-provided identities.
- Issue an auth token whenever account authentication succeeds.
- Require `Authorization: Bearer <TOKEN>` for routes that access account-owned resources.
- Original Tyto/PDF behavior returns `403` for suspicious token cases. FaceCloak uses the local project convention requested after implementation: invalid/expired tokens return `401`, forbidden authenticated operations return `403`, and hidden/private resource reads return `404`.
- Let the API find the requesting account from the token. Do not put username or user ID of the requesting user into normal API calls.
- Add resource index views for resources owned by the authenticated user.

## Scope
This plan covers the API repo only: `api/face-cloak-api`.

The Web App work is related but belongs in the app repo. API work should expose the necessary routes and response shapes so the App can later:

- Create and store a registration token in the App registration flow.
- Store authenticated account data and auth token in a secure session.
- Send `Authorization: Bearer <TOKEN>` on API requests.
- Stop sending caller identity through request params or `X-Actor-Id`.

## Completed FaceCloak State
- Authentication now returns an `authenticated_account` envelope from `POST /api/v1/auth/authenticate`.
- `FaceCloak::SecureDB` shares crypto primitives with `AuthToken` through `FaceCloak::Securable`.
- `HttpRequest` parses `Authorization: Bearer <TOKEN>` and exposes the decrypted account payload.
- Owner/assignee authorization in protected image and face-record routes now uses the token account id, not `X-Actor-Id`.
- `GET /api/v1/images` returns only images owned by the authenticated account.
- Specs now use `auth_header` and `auth_request_header` helpers.

## Tyto API Patterns to Follow
Use `../6-auth-token/tyto2026-api-6-auth-token` as the implementation reference.

### Crypto Structure
- Extract shared crypto logic into `app/lib/securable.rb`.
- Make `SecureDB` extend/use `Securable` for:
  - key generation
  - secret key setup
  - hash key setup
  - base encryption/decryption
  - keyed hash lookup
- Add `app/lib/auth_token.rb` that also extends/uses `Securable`.
- Configure `AuthToken` from `MSG_KEY` in `config/environments.rb`.

### AuthToken Behavior
- Token payload should be encrypted JSON, not signed plaintext.
- Token should include:
  - account envelope data needed by the client
  - internal account `id` needed by the API for authorization checks
  - expiration timestamp
- Implement:
  - `AuthToken.new(payload, expiration = ONE_WEEK).to_s`
  - `AuthToken.load(token).payload`
  - `fresh?`
  - `expired?`
  - `ExpiredTokenError`
  - `InvalidTokenError`
- Expired tokens should raise when payload is read.
- Tampered or malformed tokens should raise `InvalidTokenError`.

### Request Handling
- Add `plugin :request_headers` to `FaceCloak::Api`.
- Extend `HttpRequest` with `authenticated_account`.
- Parse `routing.headers['AUTHORIZATION']`.
- Accept only the `Bearer <TOKEN>` scheme.
- Store the loaded payload in `@auth_account` near the top of the main route block.
- Convert token errors to JSON `401` responses:
  - `{ message: 'Invalid auth token' }`
  - `{ message: 'Expired auth token' }`

### Auth Response Shape
Tyto returns:

```json
{
  "type": "authenticated_account",
  "attributes": {
    "account": { "type": "account", "attributes": { "...": "..." } },
    "auth_token": "..."
  }
}
```

FaceCloak should follow this pattern so the App can store the returned account and token together.

## API Tasks

### 1. Shared Crypto and AuthToken Library
- [x] Create `app/lib/securable.rb` based on Tyto's `Securable`.
- [x] Refactor `app/lib/secure_db.rb` to delegate encryption/decryption/hash behavior to `Securable`.
- [x] Create `app/lib/auth_token.rb` based on Tyto's `AuthToken`.
- [x] Add `MSG_KEY` to `config/secrets-example.yml` for development, test, and production.
- [x] Update `config/environments.rb` to require `auth_token` and call `AuthToken.setup(ENV.delete('MSG_KEY'))`.
- [x] Add or update Rake key-generation tasks so developers can generate `DB_KEY`, `HASH_KEY`, and `MSG_KEY`.

### 2. Authentication Response with Token
- [x] Update `AuthenticateAccount.call` to return an `authenticated_account` envelope.
- [x] Include the public account envelope under `attributes.account`.
- [x] Generate `attributes.auth_token` using `AuthToken`.
- [x] Include the internal account `id` inside the encrypted token payload even if the public response already includes `id`.
- [x] Keep client-facing auth errors generic: `Invalid credentials`.
- [x] Update `spec/integration/api_auth_spec.rb` and service specs so login asserts a non-empty `auth_token`.
- [x] Add a security spec that decrypts the returned token and confirms it maps to the authenticated account.

### 3. Bearer Token Parsing and Global Token Error Handling
- [x] Add `HttpRequest#authenticated_account`.
- [x] Load the authenticated account payload once in `app/controllers/app.rb`.
- [x] Rescue `AuthToken::InvalidTokenError` and `AuthToken::ExpiredTokenError` in the main route.
- [x] Add spec helpers:
  - `auth_header(account)`
  - `auth_request_header(account)`
- [x] Add unit specs for valid, expired, malformed, and tampered tokens.

### 4. Replace `X-Actor-Id` as Authorization Source
- [x] Remove caller identity trust from `X-Actor-Id` in normal protected routes.
- [x] Derive `current_account_id` from `@auth_account.dig('attributes', 'id')`.
- [x] Require authentication before protected image and face-record write routes.
- [x] For image upload, set `owner_id` from the auth token, not from a header or request body.
- [x] For image raw access, logs, face-record creation, delete, assignment, unassignment, and response routes, compare resource ownership/assignment against `current_account_id`.
- [x] Return `401` when authentication is missing, invalid, or expired; return `403` when an authenticated caller is not allowed to perform a forbidden operation.
- [x] Keep public/filtered image read behavior explicit:
  - If unauthenticated reads are intentionally allowed, they must never reveal raw private image data.
  - Raw image and logs must require a valid owner token.

### 5. Account-scoped Resource Index Routes
- [x] Change `GET /api/v1/images` to return only images owned by the authenticated account.
- [x] Keep assigned face-record visibility available through the authenticated account envelope's `face_assignments`; no separate assigned-resource index was added.
- [x] Ensure no index route accepts requester username/user id as input.
- [x] Update README endpoint documentation to describe token-based identity.

### 6. Registration Verification API Support
The PDF allows the email verification email to be sent by either App or API. For this API repo, implement the API support needed by the chosen design.

Recommended API-side approach:

- [x] Add `POST /api/v1/auth/register` to accept `email` and a verification URL generated by the App registration token.
- [x] Validate email availability before sending verification email.
- [x] Add a `VerifyRegistration` service similar to Tyto's `app/services/verify_registration.rb`.
- [x] Choose and document the email provider: Mailgun.
- [x] Mock provider calls with WebMock in tests.
- [x] Return `202` when verification email is accepted for sending.
- [x] Store the actual account only after the App validates email and submits password to `POST /api/v1/accounts`.

If the team decides the App sends verification email instead:

- [x] Keep API responsible for email availability checks before sending verification email.
- [x] Keep `POST /api/v1/accounts` as the final account creation endpoint after verified token return.
- [x] Document clearly that RegistrationToken belongs to the App repo, not this API repo.

### 7. Specs and Regression Updates
- [x] Update all integration specs that currently use `X-Actor-Id`.
- [x] Add missing-token tests for protected routes.
- [x] Add invalid-token and expired-token tests for protected routes.
- [x] Add cross-account tests:
  - non-owner cannot delete image
  - non-owner cannot read raw image
  - non-owner cannot assign/unassign face records
  - non-assignee cannot respond to a face record
  - owner cannot respond unless they are the assigned user
- [x] Add image index spec proving only current account's images are returned.
- [x] Add auth token unit tests equivalent to Tyto's `spec/unit/auth_token_spec.rb`.
- [x] Keep existing privacy behavior specs for filtered image output.

### 8. Documentation and Deployment Config
- [x] Update README authentication section to document:
  - login endpoint response
  - `Authorization: Bearer <TOKEN>` requirement
  - route-level authorization rules
  - removal/deprecation of `X-Actor-Id`
- [x] Update `config/secrets-example.yml` with `MSG_KEY`.
- [x] Note Heroku config requirement:
  - `heroku config:set MSG_KEY=<base64-32-byte-key>`
- [x] Confirm production still has `DB_KEY`, `HASH_KEY`, `DATABASE_URL`, `SECURE_SCHEME=https`, and storage settings.

## Suggested Implementation Order
1. Add `Securable`, refactor `SecureDB`, and verify existing encrypted DB specs still pass.
2. Add `AuthToken` plus unit tests.
3. Wire `MSG_KEY` into environment config and key-generation docs/tasks.
4. Update `AuthenticateAccount` to issue token and update auth specs.
5. Add `HttpRequest#authenticated_account` and global token error handling.
6. Add spec auth helpers.
7. Convert image routes from `X-Actor-Id` to `current_account_id`.
8. Convert face-record routes from `X-Actor-Id` to `current_account_id`.
9. Lock down or explicitly document public filtered image routes.
10. Change image index routes to account-scoped results.
11. Add registration verification route/service if API is responsible for email.
12. Update README and secrets examples.
13. Run full verification.

## Verification Commands
Run these after implementation:

```sh
bundle install
rake db:migrate
RACK_ENV=test rake db:migrate
rake spec
rake style
rake audit
rake release_check
```

If `rake audit` needs network access, record whether it passed or was blocked.

## Verification Results
- `bundle install`: passed after adding test-only `webmock`.
- `rake spec`: passed during `release_check`, 91 runs, 213 assertions.
- `rake style`: passed, 67 files inspected, no offenses.
- `rake audit`: passed, no vulnerabilities found.
- `rake release_check`: passed and reported `Ready for release!`.

## Important Notes
- Do not trust `X-Actor-Id`, request body `owner_id`, username, or user id for the requesting actor after this milestone.
- Bearer token parsing should be strict: missing, malformed, tampered, or expired token means unauthenticated and should be `401`.
- Auth token payload can include internal `id` because it is encrypted, but do not expose extra internal authorization data in public JSON unless the App needs it.
- Keep token keys separate from DB encryption keys. `MSG_KEY` should not reuse `DB_KEY` or `HASH_KEY`.
- Token expiration must be testable without waiting in real time. Follow Tyto's pattern of passing a negative expiration for expired-token specs.
- File upload routes cannot rely on JSON request parsing, but they still need the current account from the Bearer token.
- Public filtered image rendering is acceptable only if raw bytes, action logs, and write operations remain protected.
- Any registration email provider call must be isolated behind a service and mocked in tests with WebMock.
- Production secrets must not be committed.
- Update docs and tests at the same time as route behavior changes so the old `X-Actor-Id` contract does not survive accidentally.

## Completion Criteria
- `POST /api/v1/auth/authenticate` returns an authenticated-account envelope with a valid encrypted auth token.
- `AuthToken` unit tests cover valid, expired, invalid, and tampered token behavior.
- Protected routes derive caller identity from `Authorization: Bearer <TOKEN>`.
- No protected route trusts `X-Actor-Id` as the caller identity.
- Account-scoped index routes return only resources visible to the authenticated account.
- API-side registration verification responsibilities are implemented or explicitly documented as App-owned.
- README and secrets examples document `MSG_KEY` and Bearer-token usage.
- Full spec/style/release verification passes or any blocker is recorded.
