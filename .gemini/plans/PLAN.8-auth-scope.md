# PLAN.8-auth-scope

## Requirement Source

- PDF: `8-auth-scope/SEC Project - 011 Auth Scopes and SSO.docx.pdf`
- Target API: `face-cloak-api`
- Scope of this plan: API-side changes only. Web App work is captured only where it defines the API contract.

## Requirement Summary

This phase has two required API surfaces:

1. Auth scopes
   - Add an `AuthScope` library for scope strings such as `*:read`.
   - Add scope to every auth token, including session tokens and API keys.
   - Default session login tokens to full access.
   - Add an account-detail route that returns a limited-scope auth token.
   - Extract scope from incoming tokens and pass it through service objects to policy objects.
   - Make policy objects evaluate role/ownership rules inside the supplied scope.

2. Google OAuth/OIDC SSO
   - Do not use Google's packaged SSO gems.
   - Use `http` and `jwt` only.
   - Add `POST /api/v1/auth/sso`.
   - API receives an OIDC `id_token` and JWKS data from the App.
   - API verifies the token, extracts identity details, creates an account if needed, and returns account + auth token data.

## Existing Tyto API Style To Preserve

- Roda controllers live in `app/controllers/*`, use `route('...')`, `routing.halt`, JSON hashes, and explicit rescue blocks.
- Business logic belongs in service objects under `app/services`, usually with `self.call(...)` and nested error classes.
- Authorization belongs in policy objects under `app/policies`; controllers pass `auth_scope:` into policies/services rather than re-checking scope ad hoc.
- Auth responses use envelopes like:

```ruby
{
  type: 'authenticated_account',
  attributes: { account: account_envelope, auth_token: token }
}
```

- Tests use Minitest + Rack::Test under `spec/integration`, unit specs under `spec/unit`, and policy specs under `spec/policies`.
- Secrets are read through Figaro from `config/secrets.yml`; new config keys should also be added to `config/secrets-example.yml`.

## Current State After Implementation

- `AuthScope`, scoped `AuthToken`, `AuthorizedAccount`, and `AuthorizeAccount` exist in `face-cloak-api`.
- `HttpRequest#authorized_account` reconstructs account payload + scope from Bearer tokens.
- Account, image, and face-record policies accept `auth_scope:` and gate read/write operations.
- `GET /api/v1/accounts/[username]` returns an `AuthorizedAccount` envelope with a read-only token.
- `POST /api/v1/auth/sso` verifies Google OIDC tokens using JWT/JWKS and returns the standard auth envelope.
- SSO account persistence uses `sso_provider`, `sso_subject`, nullable `password_digest`, and optional `avatar`.
- `face-cloak-api` has no system-role management endpoint, so system-role route gating is not applicable in this branch.

## Implementation Plan

### 1. Normalize AuthScope behavior

- [x] Keep `app/lib/auth_scope.rb` as the canonical parser.
- [x] Add validation for malformed scope strings.
- [x] Reject blank scope entries.
- [x] Reject entries without `resource:permission`.
- [x] Allow only `read` and `write`.
- [x] Keep `write` implying `read`.
- [x] Preserve `AuthScope::FULL = '*:write'`.
- [x] Preserve `AuthScope::READ_ONLY = '*:read'`.
- [x] Add unit specs for malformed scopes and multi-scope strings.

### 2. Finish scope propagation across account authorization

- [x] Update `AccountPolicy` to accept `auth_scope: AuthScope.new`.
- [x] Add `RESOURCE = 'accounts'`.
- [x] Gate `can_view?` with `accounts:read` or wildcard read.
- [x] Gate `can_edit?`, `can_delete?`, `can_assign_role?`, and `can_revoke_role?` with `accounts:write` or wildcard write.
- [x] Keep actor capabilities such as `is_admin?` role-based, but make mutating capabilities scope-aware when exposed for the current request.
- [x] Confirmed no `SystemRolePolicy`/system-role management route exists in `face-cloak-api`; no implementation needed.
- [x] Confirmed account write scope is enforced on available mutating account/resource surfaces.
- [x] Update controller call sites in `app/controllers/accounts.rb` to pass `auth_scope: @auth.scope`.
- [x] Update `AuthorizeAccount` so the policy check uses the caller's incoming token scope.
- [x] Keep returned API key scope configurable via `issued_scope: AuthScope::READ_ONLY`.

### 3. Keep token response compatibility

- [x] Keep password login returning `type: 'authenticated_account'`.
- [x] Ensure `AuthenticateAccount` mints full-scope session tokens by default.
- [x] Ensure account detail mints a read-only API token distinct from the caller's session token.
- [x] Add an integration spec proving a full session token can still perform allowed writes.
- [x] Add an integration spec proving a read-only token can read account details.
- [x] Confirmed `face-cloak-api` has no account edit endpoint; read-only write denial is covered through image upload/delete.
- [x] Confirmed `face-cloak-api` has no system-role assign/revoke endpoint.
- [x] Add an integration/unit spec proving old token shapes without `scope` fail clearly or are intentionally treated as invalid.

### 4. Add SSO configuration and dependencies

- [x] Add `gem 'jwt', '~> 3.2'` to `Gemfile`.
- [x] Keep using existing `http` gem.
- [x] Do not add Google OAuth gems.
- [x] Add `GOOGLE_CLIENT_ID` to `config/secrets-example.yml`.
- [x] Add `GOOGLE_ISSUERS` to `config/secrets-example.yml`, defaulting to `https://accounts.google.com,accounts.google.com`.
- [x] In tests, set a deterministic fake Google client ID through `config/secrets.yml` or existing test env handling.

### 5. Add SSO persistence support

- [x] Add an additive migration for `sso_provider`.
- [x] Add an additive migration for `sso_subject`.
- [x] Add a unique index on provider + subject when present.
- [x] Make password optional for SSO-created accounts.
- [x] Prefer making `password_digest` nullable.
- [x] Update `Account#password?` to return false when no digest exists.
- [x] Keep email encrypted and searchable via existing `email_hash`.
- [x] Find existing SSO accounts by `sso_provider + sso_subject`.
- [x] Reuse or link an existing account by verified email hash when no provider-subject match exists.
- [x] Create a new account when no SSO identity or verified email match exists.
- [x] Generate unique usernames from the email local-part.
- [x] Append a stable short suffix from provider subject when a generated username conflicts.

### 6. Implement OIDC token verification service

- [x] Add `app/services/verify_google_id_token.rb` or `app/services/authenticate_sso_account.rb`.
- [x] Support this service input:

```json
{
  "provider": "google",
  "id_token": "...",
  "jwks": { "keys": [] }
}
```

- [x] Decode JWT header to select matching JWKS `kid`.
- [x] Verify signature with RS256 through `jwt`.
- [x] Verify `aud` equals `GOOGLE_CLIENT_ID`.
- [x] Verify `iss` is one of configured Google issuers.
- [x] Verify `exp`, `iat`, and token freshness through JWT checks.
- [x] Require `sub`.
- [x] Require `email`.
- [x] Require `email_verified == true`.
- [x] Extract `email`, `name`, `picture`, and `sub`.
- [x] Map missing fields to 400.
- [x] Map invalid token/signature/audience/issuer to 401.
- [x] Map unsupported provider to 400.
- [x] Map account creation failure to 500.

### 7. Add `/api/v1/auth/sso`

- [x] Extend `app/controllers/auth.rb`.
- [x] Add this route:

```text
POST /api/v1/auth/sso
```

- [x] Parse JSON with `HttpRequest#body_data`.
- [x] Call `AuthenticateSsoAccount.call(...)`.
- [x] Return the same envelope shape as password login.
- [x] Mint a full-scope session token using existing `AuthToken` flow.
- [x] Keep route naming and rescue style consistent with `authenticate` and `register`.

### 8. Update account envelope for SSO users

- [x] Preserve existing `Account#to_json` shape: `type`, `attributes`, `include`.
- [x] Include avatar when available if the Web App needs it; the model already has an `avatar` column.
- [x] Ensure SSO-created account responses include capabilities generated through `AccountPolicy`, same as password login.

### 9. Add tests

- [x] Add `spec/unit/auth_scope_spec.rb` coverage for validation and read/write semantics.
- [x] Add `spec/unit/auth_token_spec.rb` coverage for scope round trip and missing/invalid scope behavior.
- [x] Add SSO verifier coverage through `spec/integration/api_auth_spec.rb`.
- [x] Test valid JWT verification.
- [x] Test invalid signature rejection.
- [x] Test wrong audience rejection.
- [x] Test wrong issuer rejection.
- [x] Test unverified email rejection.
- [x] Test missing JWKS `kid` rejection.
- [x] Add account/image/face-record read-only gating coverage.
- [x] Keep existing FaceCloak account/image/face-record specs green.
- [x] Add an integration spec proving `POST /api/v1/auth/sso` creates a new account and returns account + full-scope auth token.
- [x] Add an integration spec proving repeated SSO login returns the existing account.
- [x] Add an integration spec proving verified email matching an existing local account links or reuses that account according to the chosen persistence rule.
- [x] Add an integration spec proving invalid SSO token returns 401.
- [x] Add an integration spec proving unsupported provider or malformed body returns 400.
- [x] Use generated local RSA keys in specs.
- [x] Do not call Google during tests.

### 10. Documentation and API contract

- [x] Update `README.md` or API docs with scoped token behavior.
- [x] Document `GET /api/v1/accounts/[username]` returning a read-only API key.
- [x] Document `POST /api/v1/auth/sso` request and response examples.
- [x] Document that the Web App performs the OAuth browser flow and passes `id_token` + JWKS to the API.
- [x] Update `docs/schema.md` if SSO columns are added.

## Verification

Run from `face-cloak-api`:

```sh
bundle install
bundle exec rake spec
bundle exec rubocop .
bundle audit check --update
```

Minimum acceptance criteria:

- [x] All existing auth-scope behavior remains green.
- [x] Read-only tokens cannot perform covered writes through protected resource endpoints.
- [x] Password login still returns a full-scope session token.
- [x] Account detail returns a read-only token.
- [x] SSO login verifies Google OIDC claims, creates or reuses an account, and returns the same authenticated-account envelope as password login.
- [x] No Google packaged SSO gems are introduced.

## Risks And Decisions To Confirm

- The PDF says the API receives JWKS from the App. This plan follows that literally. If the instructor expects the API to fetch Google JWKS itself, keep the verifier service but add an HTTP JWKS fetch path with test stubs.
- Account linking by verified email is convenient but has security implications. Restrict it to verified Google emails and store provider subject once linked.
- Existing sessions without token scope should be cleared by the Web App. API-side fallback to full scope would be less disruptive but weakens the requirement; prefer invalidating old token shapes.
