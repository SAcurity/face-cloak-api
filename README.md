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
- Python 3 for face/image processing dependencies

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
# Generate keys
rake newkey:db
rake newkey:hash
rake newkey:auth
```

### 3. Run Server
```bash
bundle exec rake db:migrate
# Fresh dev DB only; seeds are not intended to be rerun repeatedly on existing data.
bundle exec rake db:seed
bundle exec rake rerun
```

The API listens on `http://localhost:3000`; v1 routes are under `http://localhost:3000/api/v1`.

## Documentation
- **API Reference**: [docs/api_v1.md](docs/api_v1.md)
- **Database Schema**: [docs/schema.md](docs/schema.md)
