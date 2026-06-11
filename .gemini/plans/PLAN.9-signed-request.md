# PLAN.9-signed-request

## Requirement Source

- PDF: `9-signed-request/SEC Project - 012 Client-Side Security.docx.pdf`
- Reference implementation: `9-signed-request/tyto2026-api-9-signed-requests`
- Target API: `face-cloak-api`
- Scope of this plan: API-side changes only. Web App/browser work is listed only where it defines the API contract or an API endpoint.

## Requirement Summary

This phase asks the system to trust the client application and to ask browsers to enforce client-side protections.

1. Google OAuth CSRF prevention
   - Web App creates a Google OAuth `state` nonce and stores it in its session.
   - Web App checks returned `state` on the OAuth callback.
   - API impact is limited because `face-cloak-api` currently accepts an already-issued Google `id_token`; it does not own the OAuth redirect/callback session.

2. Signed client requests
   - API must require signed requests for routes that cannot provide an `auth_token`.
   - API verifies signed JSON payloads using a public verify key.
   - Client sends `{ data: <json>, signature: <base64> }`.

3. Browser security directives
   - Add `app/controllers/security.rb`.
   - Move API security-header behavior out of `config/environments.rb` where practical.
   - Set cookie/security/CSP headers.
   - Add a CSP report endpoint.

4. Asset integrity
   - Browser-served third-party scripts, stylesheets, and fonts need SRI hashes.
   - `face-cloak-api` does not currently serve HTML or third-party browser assets, so API work is an audit/documentation item unless assets are later added.

## Existing Tyto API Style To Preserve

- Keep small libraries under `app/lib` with explicit setup methods, e.g. `SignedRequest.setup(...)`.
- Put request parsing in `HttpRequest`; controllers should call helper methods such as `body_data` or `signed_body_data`.
- Controllers should remain thin Roda route blocks, use `routing.halt`, JSON hashes, and explicit rescue blocks for expected security failures.
- Secrets are read through Figaro and removed from `ENV` during startup.
- Tests use Minitest + Rack::Test; unit specs cover crypto libraries and integration specs prove route-level enforcement.
- Key generation belongs in `Rakefile` under `namespace :newkey`.

## Current Face Cloak State

- SSO already exists as `POST /api/v1/auth/sso` and verifies Google OIDC `id_token` + `jwks`.
- Scoped Bearer tokens already exist via `AuthToken`, `AuthScope`, and `AuthorizedAccount`.
- `auth/authenticate`, `auth/register`, `auth/sso`, `accounts`, and `accounts/search` currently read unsigned JSON via `HttpRequest#body_data`.
- Authenticated JSON mutations also read unsigned bodies, but they already require Bearer tokens and scope checks.
- Multipart image upload cannot use the same signed JSON body format and already requires a Bearer token.
- Production security behavior is split between `config/environments.rb` plugins and `app/controllers/app.rb`; there is no dedicated security controller.

## Implementation Status

- `SignedRequest` is implemented under `app/lib/signed_request.rb`.
- `HttpRequest#signed_body_data` verifies `{ data, signature }` request bodies.
- Public POST routes without Bearer tokens now require signed JSON:
  - `POST /api/v1/auth/authenticate`
  - `POST /api/v1/auth/register`
  - `POST /api/v1/auth/sso`
  - `POST /api/v1/accounts`
  - `POST /api/v1/accounts/search`
- Authenticated mutation routes continue to rely on Bearer tokens, auth scopes, and policies.
- `app/controllers/security.rb` applies browser security headers and exposes `POST /api/v1/security/csp-report`.
- `docs/api_v1.md` documents signed requests, OAuth state ownership, CSP reports, and asset-integrity responsibility.
- Tests cover signed-request crypto, unsigned public POST rejection, security headers, CSP reports, and existing auth/account/SSO flows.
- Verified with `rake spec`, `rubocop --cache false .`, and `bundle audit check`.

## Implementation Plan

### 1. Add SignedRequest library

- [x] Add `app/lib/signed_request.rb` under `FaceCloak`.
- [x] Use `rbnacl` Ed25519 signing/verification, matching Tyto's `RbNaCl::SigningKey` and `RbNaCl::VerifyKey` pattern.
- [x] Store keys as strict Base64 strings.
- [x] Implement `SignedRequest.setup(verify_key64, signing_key64 = nil)`.
- [x] Implement `SignedRequest.generate_keypair`.
- [x] Implement `SignedRequest.parse(signed)` returning `signed[:data]` after verification.
- [x] Implement `SignedRequest.sign(message)` for test/dev only when `SIGNING_KEY` is configured.
- [x] Raise `SignedRequest::VerificationError` for forged, missing, malformed, or tampered signatures.
- [x] Raise `SignedRequest::KeypairError` for invalid key setup or test signing without a signing key.
- [x] Keep production API verify-only: production config must not require or store `SIGNING_KEY`.

### 2. Wire signed request configuration

- [x] Require `app/lib/signed_request` from `config/environments.rb`.
- [x] Add `SignedRequest.setup(ENV.delete('VERIFY_KEY'), ENV.delete('SIGNING_KEY'))` during startup.
- [x] Require `VERIFY_KEY` in every environment.
- [x] Allow `SIGNING_KEY` only in test/dev where local specs or manual clients need to sign messages.
- [x] Add `VERIFY_KEY` and optional test/dev `SIGNING_KEY` to `config/secrets-example.yml`.
- [x] Add `newkey:signing` rake task that prints both keys, matching Tyto style:

```text
SIGNING_KEY: ...
 VERIFY_KEY: ...
```

### 3. Add signed body parsing

- [x] Add `HttpRequest#signed_body_data`.
- [x] Keep `HttpRequest#body_data` as the unsigned JSON parser for authenticated or non-JSON use cases.
- [x] `signed_body_data` should call `SignedRequest.parse(body_data)`.
- [x] Support symbolized JSON keys consistently with current `body_data`.
- [x] Do not apply signed JSON parsing to multipart upload.

### 4. Require signatures on public POST routes

Require signed JSON for POST routes that do not require a Bearer `auth_token`:

- [x] `POST /api/v1/auth/authenticate`
- [x] `POST /api/v1/auth/register`
- [x] `POST /api/v1/auth/sso`
- [x] `POST /api/v1/accounts`
- [x] `POST /api/v1/accounts/search`

Controller behavior:

- [x] Replace `HttpRequest.new(routing).body_data` with `signed_body_data` on these public routes.
- [x] Rescue `SignedRequest::VerificationError`.
- [x] Return `403` with a stable message such as `{ message: 'Must sign request' }`.
- [x] Keep existing domain errors and status codes after signature verification succeeds.
- [x] Preserve existing response envelope shapes for login, registration, SSO, account creation, and account search.

### 5. Decide handling for authenticated mutation routes

Authenticated mutations already prove caller identity through Bearer tokens and `AuthScope`:

- `PUT /api/v1/accounts/:username`
- `DELETE /api/v1/accounts/:username`
- `POST /api/v1/images`
- `DELETE /api/v1/images/:id`
- `POST /api/v1/images/:id/face_records`
- `POST /api/v1/face_records/:id/assignment`
- `DELETE /api/v1/face_records/:id/assignment`
- `POST /api/v1/face_records/:id/respond`
- `POST /api/v1/face_records/:id/decline`

Plan decision:

- [x] Keep Bearer token + policy/scope enforcement as the minimum requirement-compliant path.
- [x] Do not force signed JSON on multipart image upload.
- [x] Decided not to add `signed_or_authorized_body_data` now; authenticated mutations remain protected by Bearer token, scope, and policies.
- [x] Add a short docs note explaining that unsigned public POST is forbidden, while authenticated mutations are protected by Bearer token and scope.

### 6. Preserve OAuth state nonce boundary

- [x] Do not add API sessions solely for Google OAuth `state`; current API does not initiate OAuth redirects.
- [x] Document that the Web App must generate, store, and verify the Google OAuth `state` nonce before calling `POST /api/v1/auth/sso`.
- [x] Because `POST /api/v1/auth/sso` becomes signed, require the client to sign the final `{ provider, id_token, jwks }` payload sent to the API.
- [x] Future API-owned OAuth redirect flow is out of scope; current token-verification endpoint remains separate.

### 7. Add security controller and headers

- [x] Create `app/controllers/security.rb`.
- [x] Define a small controller/helper surface for security headers, for example `apply_security_headers`.
- [x] Call the security header helper from the top-level route in `app/controllers/app.rb` before route dispatch.
- [x] Move production-only HSTS/HTTPS behavior out of `config/environments.rb` where practical:
  - remove duplicated `plugin :hsts` from environment config if headers are set manually;
  - keep or centralize HTTPS redirect behavior in one place only.
- [x] Set strict default headers:
  - `Strict-Transport-Security` in production HTTPS responses;
  - `X-Content-Type-Options: nosniff`;
  - `X-Frame-Options: DENY`;
  - `Referrer-Policy: no-referrer`;
  - `Permissions-Policy` disabling browser capabilities the API does not use;
  - `Cache-Control: no-store` for auth responses or other sensitive JSON where appropriate.
- [x] Set a conservative CSP for API responses, such as `default-src 'none'; frame-ancestors 'none'; base-uri 'none'; form-action 'none'`, with report configuration.
- [x] Do not set cookies from the API unless a route explicitly needs cookies; if cookies are introduced, set `Secure`, `HttpOnly`, and `SameSite`.

### 8. Add CSP report endpoint

- [x] Add `POST /api/v1/security/csp-report`.
- [x] Accept browser reports without signed request verification because browsers cannot attach the app's client signature to automatic CSP reports.
- [x] Accept common CSP report content types:
  - `application/csp-report`
  - `application/reports+json`
  - `application/json`
- [x] Parse reports defensively and log only sanitized fields such as blocked URI, violated directive, document URI, and source file.
- [x] Return `204 No Content` on accepted reports.
- [x] Return `400` on malformed JSON only if the report is unreadable.
- [x] Add the report URI to the CSP header.

### 9. Asset integrity audit

- [x] Search `face-cloak-api` for served HTML, templates, public assets, third-party scripts, stylesheets, and fonts.
- [x] If no browser assets are served by the API, document "not applicable to API; Web App must provide SRI hashes".
- [x] Browser asset SRI rake task is not applicable now because this API does not serve third-party browser assets.

### 10. Tests

- [x] Add `spec/unit/signed_request_spec.rb`.
- [x] Test generated keys are Base64-encoded 32-byte Ed25519 keys.
- [x] Test signed payload round trip.
- [x] Test forged signature rejection.
- [x] Test tampered payload rejection.
- [x] Test missing signature rejection.
- [x] Test invalid key setup rejection.
- [x] Test verify-only setup refuses to sign.
- [x] Add integration coverage proving unsigned public POST routes return `403`:
  - `auth/authenticate`
  - `auth/register`
  - `auth/sso`
  - `accounts`
  - `accounts/search`
- [x] Update existing auth/account integration specs to wrap public POST bodies in `FaceCloak::SignedRequest.sign(...)`.
- [x] Add security header specs for root and API routes.
- [x] Add CSP report endpoint specs for valid report, malformed report, and no signature required.
- [x] Keep existing scoped-token and SSO specs green.

### 11. Documentation

- [x] Update `README.md` or `docs/api_v1.md` with signed request format:

```json
{
  "data": {
    "username": "alice",
    "password": "secret"
  },
  "signature": "base64-ed25519-signature"
}
```

- [x] Document that signatures are calculated over `data.to_json`, matching the API verifier.
- [x] Document API config keys:
  - `VERIFY_KEY`
  - `SIGNING_KEY` for test/dev only
- [x] Document public POST routes that require signatures.
- [x] Document Web App responsibilities:
  - store and verify Google OAuth `state`;
  - hold the signing key securely;
  - sign public critical requests;
  - add SRI hashes to third-party browser assets.

## Verification

Run from `face-cloak-api`:

```sh
bundle install
bundle exec rake spec
bundle exec rubocop .
bundle audit check --update
```

Minimum acceptance criteria:

- [x] Public POST routes without Bearer tokens reject unsigned bodies with `403`.
- [x] Signed public POST routes preserve existing success behavior and response envelopes.
- [x] Invalid, missing, or tampered signatures never reach service objects.
- [x] Production API can verify signed requests without a configured signing key.
- [x] Existing Bearer-token protected routes still enforce `AuthScope` and policies.
- [x] Security headers are present on JSON API responses.
- [x] CSP reports can be posted by the browser without client signatures.
- [x] No API-served third-party browser asset lacks an integrity plan.

## Risks And Decisions To Confirm

- `SignedRequest.verify` signs `message.to_json`; JSON key order must be identical between client and server. Tyto accepts this tradeoff, but a canonical JSON encoder would be more robust if clients are not Ruby/JavaScript-controlled.
- Requiring signed requests for `POST /api/v1/accounts/search` reduces forged requests but does not itself prevent account enumeration. Consider requiring Bearer auth later if account search should be private.
- CSP is most valuable on the Web App, not a JSON-only API. The API should still expose strict headers and a report endpoint, but frontend CSP/SRI must be implemented in the Web App repo.
- Automatic CSP reports cannot be signed. The report endpoint must be deliberately exempt from signed-request enforcement and rate-limited at infrastructure level if exposed publicly.
