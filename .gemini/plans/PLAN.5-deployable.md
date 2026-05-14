# 5-deployable - API Admin Bootstrap and Heroku Readiness [COMPLETED]

## Goal
Prepare the FaceCloak API for this week's deployable milestone by aligning with the Tyto deployable API execution style, confirming registration support, adding an admin bootstrap Rake task, and making the API ready for Heroku/Postgres deployment.

## Scope
This plan is intentionally API-only for the current repo: `api/face-cloak-api`.

The Web App work lives in a separate path and will be handled after the API is complete. App-only work such as HTTPS/HSTS redirects, WebMock service tests, registration form flow, encrypted client session state, and `MSG_KEY` handling is deferred to the App repo.

## Strategy
1. **Reference Tyto API**: Use `../5-deployable/tyto2026-api-5-deployable` as the execution and code-style reference.
2. **Registration Endpoint Check**: Confirm the API accepts registration payloads from the App through `POST /api/v1/accounts`.
3. **Admin Bootstrap Task**: Add an idempotent Rake task to promote a selected account to admin role.
4. **Heroku Readiness**: Ensure the API can run against Heroku Postgres with production secrets and deployment commands.
5. **S3 Image Storage**: Use local disk for development/test and S3 for production image objects.
6. **Verification**: Run migrations, specs, style, and release checks following the existing project/Tyto flow.

## Reference Implementation
Use `../5-deployable/tyto2026-api-5-deployable` as the primary reference for API execution method and Ruby/Roda code style.

### Tyto API Execution Method to Follow
- Install dependencies with Bundler:
  `bundle install`.
- Copy `config/secrets-example.yml` to `config/secrets.yml` before local execution.
- Run migrations with `rake db:migrate`.
- Run the API locally with `puma`, `rake puma`, or the project Rake task pattern.
- Prepare test databases with `RACK_ENV=test rake db:migrate`.
- Run tests with `rake spec`.
- Run final verification with `rake release_check`, which should include specs, RuboCop style checks, and bundle audit.

### Tyto API Code Style to Follow
- Keep `# frozen_string_literal: true` at the top of Ruby files.
- Use Roda with `plugin :halt`, `plugin :all_verbs`, and `plugin :multi_route` for API route organization.
- Keep controllers thin: parse requests, call service objects, set response status/headers, and translate service errors into JSON responses.
- Use `HttpRequest` for shared request concerns, especially TLS enforcement and JSON body parsing.
- Use service objects with `.call(...)` entry points for business logic.
- Define small domain-specific error classes inside service objects where useful.
- Return consistent JSON envelopes such as `{ message: ..., data: ... }` or model `to_json` output already used by this project.
- Use idempotent behavior for role/bootstrap tasks.
- Match Tyto Rake task structure: use `require_app`, load models/services explicitly, provide clear `desc` strings, and abort early for missing required input.
- Log unknown server-side errors, but return generic client-facing error messages.

## API Tasks

### 1. Registration Endpoint Support
- [x] Confirm `POST /api/v1/accounts` accepts `email`, `username`, and `password`.
- [x] Confirm account creation goes through the existing API service object instead of controller-only model writes.
- [x] Confirm duplicate username/email failures return a clear client-facing JSON error.
- [x] Keep note that account details are not verified in this workflow.
- [x] Add or update API specs if the existing registration coverage is incomplete.

### 2. Admin Bootstrap Rake Task
- [x] Add a Rake task such as `db:bootstrap_admin`.
- [x] Allow the task to promote a selected existing user account to the admin role.
- [x] Use required task input such as `ADMIN_USERNAME=<username>`.
- [x] Ensure required roles exist before assignment.
- [x] Ensure the task is idempotent and safe to re-run without duplicating roles.
- [x] Follow Tyto's `db:bootstrap_admin` approach for role creation, account lookup, and clear terminal output.
- [x] Abort early with a useful message when required input is missing or the account does not exist.

### 3. API Heroku/Postgres Readiness
- [x] Confirm production uses `DATABASE_URL` for Postgres.
- [x] Confirm required production secrets are documented in `config/secrets-example.yml` and README.
- [x] Confirm `Procfile` exists or add one if missing.
- [x] Document Heroku migration command: `heroku run rake db:migrate`.
- [x] Document Heroku admin bootstrap command: `heroku run rake db:bootstrap_admin ADMIN_USERNAME=<username>`.
- [x] Confirm Heroku deployment does not require local-only files except optional face detector assets already committed.
- [ ] Verify deployed API root and registration/auth routes after deployment.

### 4. API Verification
- [x] Run `rake db:migrate`.
- [x] Run `RACK_ENV=test rake db:migrate`.
- [x] Run `rake spec`.
- [x] Run `rake style`.
- [x] Run `rake audit` if network access is available.
- [x] Run `rake release_check` if all dependencies and network access are available.

## Verification Results
- `rake db:migrate`: passed.
- `RACK_ENV=test rake db:migrate`: passed.
- `rake spec`: 69 runs, 169 assertions, 0 failures after S3 storage abstraction.
- `rake style`: 62 files inspected, no offenses.
- `rake audit`: no vulnerabilities found.
- `rake release_check`: passed and reported `Ready for release!`.
- `RACK_ENV=test ADMIN_USERNAME=bootstrap_user rake db:bootstrap_admin`: passed twice; first run granted admin, second run reported the role already assigned.
- Email uniqueness is enforced directly in the initial accounts migration on `email_hash`, because this project can drop and rebuild local databases.
- Image storage now uses local disk in development/test and S3 in production via `FaceCloak::ImageStorage`.

## Environment Variables
- `DATABASE_URL`: API database connection string. Heroku Postgres provides this automatically.
- `DB_KEY`: Secret key for encrypted database fields.
- `HASH_KEY`: Secret key for keyed-hash lookup fields.
- `GEMINI_API_KEY`: Optional production key for Gemini fallback face detection.
- `STORAGE_PROVIDER`: `local` in development/test and `s3` in production.
- `S3_BUCKET_NAME`: Private S3 bucket for original uploaded image objects.
- `AWS_REGION`: AWS region for the S3 bucket.
- `AWS_ACCESS_KEY_ID`: S3 IAM access key for the API server.
- `AWS_SECRET_ACCESS_KEY`: S3 IAM secret key for the API server.
- `S3_ENDPOINT`: Optional S3-compatible endpoint; not needed for regular AWS S3.
- `S3_FORCE_PATH_STYLE`: Optional `true` for S3-compatible providers that require path-style access; not needed for regular AWS S3.
- `SECURE_SCHEME`: Expected request scheme, normally `https` in production if enforced by current API configuration.

## S3 Storage Notes
- Production must not rely on Heroku's ephemeral filesystem for uploaded images.
- `FaceCloak::ImageStorage` abstracts local disk and S3 object storage.
- Uploaded image DB records store object keys such as `images/<uuid>.png` in `images.file_data`.
- S3 buckets should be private; API authorization rules should gate every image read/write/delete.
- Local cache files under `tmp/storage_cache` and `db/local/storage/cache` are disposable.

## Deferred App Work
These items belong to `app/face-cloak-app` and should be completed after this API plan:

- App HTTPS redirect and HSTS for all routes.
- App WebMock tests for service objects.
- App registration form and registration controller flow.
- App service object posting registration data to this API.
- App secure messaging library using `MSG_KEY` and NaCl `SimpleBox`.
- App secure session helper using the secure messaging library.
- App Heroku deployment and configuration to talk to the deployed API.

## Risks and Notes
- The registration workflow is intentionally basic and risky because account details are not verified yet.
- The admin bootstrap task should promote only an existing account unless we explicitly choose to support account creation from the task.
- Heroku production secrets must not be committed.
- Bundle audit may require network access.
- The API and App should be deployed separately, but this plan only tracks API readiness.

## Completion Criteria
- Implementation references the Tyto deployable API example for execution method and Ruby/Roda code style.
- `POST /api/v1/accounts` supports basic unverified registration payloads for the future App flow.
- API includes a working idempotent admin bootstrap Rake task.
- API production configuration is ready for Heroku Postgres.
- API README/config docs include the required deployment and bootstrap commands.
- API specs and style checks pass, with audit/release checks run where available.
