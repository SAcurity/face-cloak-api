# FaceCloak API

Privacy-first API for face-cloaking in images.

## API Routes Index

Detailed technical specifications can be found in [docs/api_v1.md](docs/api_v1.md).

### 1. Authentication
- `POST /api/v1/auth/authenticate`
- `POST /api/v1/auth/sso`
- `POST /api/v1/auth/register`

### 2. Accounts
- `GET /api/v1/accounts`
- `POST /api/v1/accounts`
- `GET /api/v1/accounts/usernames`
- `GET /api/v1/accounts/:username`
- `PUT /api/v1/accounts/:username`
- `DELETE /api/v1/accounts/:username`
- `POST /api/v1/accounts/search`

### 3. Images
- `GET /api/v1/images`
- `POST /api/v1/images`
- `GET /api/v1/images/:id`
- `GET /api/v1/images/:id/raw`
- `GET /api/v1/images/:id/logs`
- `DELETE /api/v1/images/:id`

### 4. Face Records
- `GET /api/v1/images/:id/face_records`
- `POST /api/v1/images/:id/face_records`
- `GET /api/v1/face_records/:id`
- `POST /api/v1/face_records/:id/assignment`
- `DELETE /api/v1/face_records/:id/assignment`
- `POST /api/v1/face_records/:id/respond`
- `POST /api/v1/face_records/:id/decline`

### 5. Audit Logs
- `GET /api/v1/images/:id/logs`
- `GET /api/v1/face_records/:id/logs`

---

## Quick Start

### 0. Prerequisites
- Ruby 4.0.2
- Bundler matching `Gemfile.lock`
- Python 3.11 for local OpenCV face detection and image rendering
- SQLite for local development/test
- PostgreSQL for production, usually provided by Heroku Postgres

The API can boot without a separate local model server. Local face detection runs
inside the app through OpenCV and the checked-in YuNet model at
`vendor/models/face_detection_yunet_2023mar.onnx`; if that model is unavailable,
OpenCV falls back to its built-in Haar cascade. Gemini is used as the fallback
face detector and for AI inpainting styles.

### 1. Install Dependencies
```bash
rbenv local 4.0.2
bundle install
python3 -m venv .venv
.venv/bin/python -m pip install -r requirements.txt
```

### 2. Configuration
```bash
cp config/secrets-example.yml config/secrets.yml
rake newkey:db
rake newkey:hash
rake newkey:auth
rake newkey:signing
```

Fill the generated values into `config/secrets.yml`.

Required to boot the API:
- `DATABASE_URL`: SQLite locally, PostgreSQL in production.
- `DB_KEY`: 32-byte Base64 key for encrypted database fields.
- `HASH_KEY`: 32-byte Base64 key for deterministic lookup hashes.
- `MSG_KEY`: Base64 key for auth and registration tokens.
- `VERIFY_KEY`: public key for signed client requests.
- `SIGNING_KEY`: private signing key for local development/test clients. Do not
  set this on the production API unless the server must sign requests.
- `SECURE_SCHEME`: `http` locally, `https` in production.

Required by specific features:
- `GEMINI_API_KEY`: required for Gemini fallback face detection and AI cloak
  styles such as sunglasses, mask, comics, and pixelate. Without it, the API can
  still run and local OpenCV filters continue to work.
- `MAILGUN_API_KEY`, `MAILGUN_DOMAIN`: required for registration email.
  `MAILGUN_API_BASE_URL`, `MAILGUN_FROM_EMAIL`, and `MAILGUN_FROM_NAME` can
  override the built-in defaults.
- `GOOGLE_CLIENT_ID`: required for Google SSO. `GOOGLE_ISSUERS` can override
  the default Google issuer list.
- `ASYNC_FACE_DETECTION`: optional production flag. Set to `true` only if the
  deployment has the background execution strategy needed by your release.

### 3. Storage

Local development uses disk storage by default:

```yaml
STORAGE_PROVIDER: "local"
```

Production defaults to S3 when `STORAGE_PROVIDER` is not set. To use S3, create a
private bucket and an IAM access key that can read, write, and delete objects in
that bucket. Then configure:

```yaml
STORAGE_PROVIDER: "s3"
S3_BUCKET_NAME: "your-private-bucket"
AWS_REGION: "ap-northeast-1"
AWS_ACCESS_KEY_ID: "..."
AWS_SECRET_ACCESS_KEY: "..."
```

Optional S3-compatible storage settings:
- `S3_ENDPOINT`: custom endpoint for S3-compatible providers.
- `S3_FORCE_PATH_STYLE`: set to `true` for providers that require path-style
  bucket URLs.

### 4. Run Server
```bash
bundle exec rake db:migrate
# Fresh dev DB only; seeds are not intended to be rerun repeatedly on existing data.
bundle exec rake db:seed
bundle exec rake rerun
```

The API listens on `http://localhost:3000`; v1 routes are under `http://localhost:3000/api/v1`.

## Heroku Deployment

This project is ready for Heroku's Git deployment flow. Set production config
vars first, make sure a Heroku Postgres add-on is attached so `DATABASE_URL` is
available, then deploy by pushing the repository to the Heroku remote:

```bash
heroku config:set RACK_ENV=production
heroku config:set DB_KEY=... HASH_KEY=... MSG_KEY=... VERIFY_KEY=...
heroku config:set GEMINI_API_KEY=...
heroku config:set STORAGE_PROVIDER=s3 S3_BUCKET_NAME=... AWS_REGION=...
heroku config:set AWS_ACCESS_KEY_ID=... AWS_SECRET_ACCESS_KEY=...
heroku config:set SECURE_SCHEME=https
heroku config:set MAILGUN_API_KEY=... MAILGUN_DOMAIN=...
heroku config:set MAILGUN_FROM_EMAIL=... MAILGUN_FROM_NAME=FaceCloak
heroku config:set GOOGLE_CLIENT_ID=...
git push heroku main
heroku run bundle exec rake db:migrate
```

If your local branch is not `main`, push the correct branch explicitly, for
example `git push heroku your-branch:main`. Heroku provides `PORT` at runtime,
and `Procfile` starts Puma with `RACK_ENV=production`.

## Documentation
- **API Reference**: [docs/api_v1.md](docs/api_v1.md)
- **Database Schema**: [docs/schema.md](docs/schema.md)
