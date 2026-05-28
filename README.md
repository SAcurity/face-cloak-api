# FaceCloak API

API for configuring privacy controls for detected faces in images.

## Core Business Rules

### 1. Automated Detection
- When an image is uploaded via `POST` `/api/v1/images`, the system automatically detects faces and creates one `FaceRecord` entry for each detected face.
- All new faces default to a `blur` state.
- Duplicate file names for the same owner are automatically suffixed, such as `repeat-1.png`.

### 2. Zero-Trust Access Control
- **Owner Role**: Can upload images, create face records, assign face records, unassign face records, and view image-level logs.
- **Assignee Role**: ONLY the assigned user can decide the face's `cloak_type` or decline the assignment.
- **Privacy Barrier**: The image owner cannot respond to a face they are not assigned to.
- **Assignment Constraint**: A user can only be assigned to ONE face record per image.
- **Rendered Output**: `GET` `/api/v1/images/:id` only returns raw data if the image has face records and **ALL** faces are effectively `unveil`. Otherwise it returns a privacy-filtered image and sets `X-Privacy-Filtered: true`.

### 3. Supported Values
- **Cloak Types**: `blur`, `pixelate`, `comic`, `sunglasses`, `mask`, `unveil`
- **Action Types**: `create`, `assign`, `unassign`, `respond`, `decline`

## Routes

All routes return JSON except `GET` `/api/v1/images/:id` and `GET` `/api/v1/images/:id/raw`, which return binary image content.

### Root

- `GET` `/`
  Returns API metadata and resources.

### Authentication

- `POST /api/v1/auth/authenticate`
  Authenticates an account and returns user details plus an encrypted auth token.
  - Request body:
    - `username`
    - `password`
  - Returns `200` with:
    - `type: authenticated_account`
    - `attributes.account`: account data including roles and assignments
    - `attributes.auth_token`: token to send on protected API requests
  - Returns `403` for invalid credentials.

- `POST /api/v1/auth/register`
  Validates a prospective email and sends a registration verification email.
  - Request body:
    - `email`
    - `verification_url`
  - Returns `202` after the email provider accepts the request.
  - Returns `400` for duplicate email or invalid payload.
  - Returns `500` if the email provider rejects the request or cannot be reached.

Protected routes require:
```http
Authorization: Bearer <auth_token>
```

The API derives the current account from the encrypted token. Do not send caller identity through `X-Actor-Id`, `owner_id`, username, or user id request fields.

Status-code policy:
- `401`: missing, invalid, or expired authentication token.
- `403`: authenticated account is attempting a forbidden operation or lacks required permissions.
- `404`: resource does not exist or is intentionally hidden/private for the authenticated account.

### Accounts

- `GET /api/v1/accounts`
  Returns all accounts as a minimal list.
  - Requires `Authorization: Bearer <auth_token>`.
  - Returns `200` with:
    - `data`: array of accounts containing only `id` and `username`

- `POST /api/v1/accounts`
  Creates a new account.
  - Request body:
    - `username`
    - `email`
    - `password`
  - Returns `201` on success.
  - Returns `400` for invalid payload or duplicate username.

- `POST /api/v1/accounts/search`
  Finds an account by email.
  - Request body:
    - `email`
  - Email lookup is performed via the stored keyed hash.
  - Returns `404` if no account matches.

- `GET /api/v1/accounts/:username`
  Returns account metadata for the given username.
  - Returns `404` if the account does not exist.


### Images

- `GET` `/api/v1/images`
  Returns metadata for images owned by the authenticated account.
  - Requires `Authorization: Bearer <auth_token>`.

- `POST` `/api/v1/images`
  Uploads an image and automatically triggers face detection.
  - Request body (Multipart):
    - `file` (Uploaded image)
  - Requires `Authorization: Bearer <auth_token>`.
  - The authenticated account becomes the image owner.
  - The uploaded file is stored in local storage.
  - The API auto-creates one `FaceRecord` entry for each detected face. Each new record defaults to effective `blur`.

- `GET` `/api/v1/images/:id`
  Returns the default privacy-filtered image view.
  - **Everyone (including Owner)**: Raw binary is returned ONLY when the image has face records and ALL face records are effectively `unveil`.
  - Otherwise the API returns a rendered privacy-filtered image and sets `X-Privacy-Filtered: true`.

- `GET` `/api/v1/images/:id/raw`
  Returns the raw image binary regardless of face state.
  - **Owner ONLY**: Bearer token account must match the image owner.
  - Non-owner requests return `404` because raw images are intentionally hidden private resources.

- `GET` `/api/v1/images/:id/logs`
  Returns all action logs for all faces belonging to the specified image.
  - **Owner ONLY**: Bearer token account must match the image owner.

- `DELETE` `/api/v1/images/:id`
  Deletes an image and all associated face records and action logs.
  - **Owner ONLY**: Bearer token account must match the image owner.
  - Also removes the stored file from local storage.

### Face Records

- `GET` `/api/v1/images/:id/face_records`
  Returns face records for an owned image.
  - **Owner ONLY**: Bearer token account must match the image owner.
  - Each face record includes `assigned_user_id`, `assigned_user`, `assigned_at`, `responded_at`, and `cloak_type`.
  - `assigned_user` is `null` when unassigned; otherwise it contains `id` and `username`.

- `POST` `/api/v1/images/:id/face_records`
  Creates a face record for an existing image manually.
  - Request body:
    - `cloak_type` (optional)
  - **Owner ONLY**: Bearer token account must match the image owner.
  - Automatically creates a `create` action log.

- `GET` `/api/v1/face_records/:id`
  Returns a single face record as JSON.
  - **Owner or Assignee ONLY**: Bearer token account must match either the image owner or the record assignee.
  - Includes `assigned_user_id`, `assigned_user`, `assigned_at`, `responded_at`, and `cloak_type`.

- `POST` `/api/v1/face_records/:id/assignment`
  Assigns a face record to a user.
  - Request body:
    - `assigned_user_id`
  - **Owner ONLY**: Bearer token account must match the image owner.
  - **Constraint**: The same user can only be assigned to ONE face record within the same image.
  - Also grants image access via the `accounts_images` join table.

- `DELETE` `/api/v1/face_records/:id/assignment`
  Clears the assigned user from a face record.
  - **Owner ONLY**: Bearer token account must match the image owner.
  - Clears `assigned_user_id` and `assigned_at`.
  - Does not clear `cloak_type` or `responded_at`; any previously selected cloak type remains on the record.
  - Automatically creates an `unassign` action log.

- `POST` `/api/v1/face_records/:id/respond`
  Updates the selected cloak type for the assigned user.
  - Request body:
    - `cloak_type`
  - **Assignee ONLY**: Bearer token account must match `assigned_user_id`.
  - Automatically creates a `respond` action log.

- `POST` `/api/v1/face_records/:id/decline`
  Declines the assignment for the assigned user.
  - **Assignee ONLY**: Bearer token account must match `assigned_user_id`.
  - Clears `assigned_user_id`, `assigned_at`, and `responded_at`.
  - Resets `cloak_type` to `blur`.
  - Automatically creates a `decline` action log.

### Action Logs

- `GET` `/api/v1/images/:id/logs`
  Returns all action logs for all faces belonging to the specified image.
  - **Owner ONLY**: Bearer token account must match the image owner.

- `GET` `/api/v1/face_records/:id/logs`
  Returns all action logs for the specified face record.
  - **Owner or Assignee ONLY**: Bearer token account must match either the image owner or the record assignee.

## Install
Clone the repo first:
```bash
git clone <repository_url>
cd face-cloak-api
```

Install this API by cloning the relevant branch and installing required gems from `Gemfile.lock`:

```bash
bundle install
```

Install the local face detector runtime:
```bash
python3 -m venv .venv
.venv/bin/python -m pip install -r requirements-face-detector.txt
```

The API uses OpenCV YuNet locally for face bounding boxes before falling back to Gemini detection. The YuNet model is stored at `vendor/models/face_detection_yunet_2023mar.onnx`; `.venv` is local-only and should not be committed.

Copy config/secrets-example.yml to config/secrets.yml and adjust as needed:
```bash
cp config/secrets-example.yml config/secrets.yml
```

Required secrets:
- `DATABASE_URL`
- `DB_KEY`
- `HASH_KEY`
- `MSG_KEY`
- `GEMINI_API_KEY` (optional, used for Gemini fallback face detection)
- `STORAGE_PROVIDER` (`local` for development/test, `s3` for production)
- `S3_BUCKET_NAME`, `AWS_REGION`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` when `STORAGE_PROVIDER=s3`
- `ASYNC_FACE_DETECTION=false` keeps production uploads synchronous so face records exist before the upload response returns
- `MAILGUN_API_KEY`, `MAILGUN_API_BASE_URL`, `MAILGUN_DOMAIN`, `MAILGUN_FROM_EMAIL`, `MAILGUN_FROM_NAME` for registration verification email

You can generate sample keys with:
```bash
rake newkey:db
rake newkey:hash
rake newkey:auth
```

Setup development database once:
```bash
rake db:migrate
```

Optional seed data:
```bash
rake db:seed
```

Promote an existing account to admin:
```bash
ADMIN_USERNAME=alice rake db:bootstrap_admin
```

Optional detector check:
```bash
.venv/bin/python app/lib/opencv_face_detector.py db/seeds/files/3-people.png
```

## Test
Setup test database once:

```bash
RACK_ENV=test rake db:migrate
```

Run the test script:
```bash
rake spec
```

If the Python detector runtime is not installed, detector-specific tests skip the local seed-image assertion and the app falls back to Gemini detection at runtime.

## Run
Run this API using:
```bash
rake puma
```

Or you can rerun the API using:
```bash
rake rerun
```

Both commands default to port `3000`. Override it with `PORT=xxxx` when needed.

## Deploy to Heroku
Create the Heroku app and attach Postgres:
```bash
heroku create <face-cloak-api-app-name>
heroku addons:create heroku-postgresql --app <face-cloak-api-app-name>
```

Configure production secrets. Generate `DB_KEY`, `HASH_KEY`, and `MSG_KEY`
locally with `rake newkey:db`, `rake newkey:hash`, and `rake newkey:auth`,
then set them on Heroku:
```bash
heroku config:set DB_KEY=<base64-db-key> HASH_KEY=<base64-hash-key> MSG_KEY=<base64-msg-key> SECURE_SCHEME=https STORAGE_PROVIDER=s3 --app <face-cloak-api-app-name>
heroku config:set GEMINI_API_KEY=<gemini-api-key> --app <face-cloak-api-app-name>
heroku config:set MAILGUN_API_KEY=<mailgun-api-key> MAILGUN_API_BASE_URL=https://api.mailgun.net MAILGUN_DOMAIN=<mailgun-domain> MAILGUN_FROM_EMAIL=<verified-sender-email> MAILGUN_FROM_NAME=FaceCloak --app <face-cloak-api-app-name>
```

Create a private S3 bucket for image storage. Do not make the bucket public;
the API should enforce FaceCloak ownership/privacy rules before reading image
bytes and returning them to the Web App. Grant the IAM user only the minimum
bucket permissions needed for this app: `s3:PutObject`, `s3:GetObject`,
and `s3:DeleteObject` on the bucket's objects. The `HeadObject` API used for
existence checks is covered by `s3:GetObject`.

Configure S3 credentials on Heroku:
```bash
heroku config:set S3_BUCKET_NAME=<private-bucket-name> AWS_REGION=<aws-region> \
  AWS_ACCESS_KEY_ID=<access-key-id> AWS_SECRET_ACCESS_KEY=<secret-access-key> \
  --app <face-cloak-api-app-name>
```

For regular AWS S3, `S3_ENDPOINT` and `S3_FORCE_PATH_STYLE` are not needed.
Only set them for S3-compatible providers:
```bash
heroku config:set S3_ENDPOINT=<provider-endpoint> S3_FORCE_PATH_STYLE=true --app <face-cloak-api-app-name>
```

Deploy and prepare the database:
```bash
git push heroku main
heroku run rake db:migrate --app <face-cloak-api-app-name>
```

Create a user through `POST /api/v1/accounts`, then promote that existing user:
```bash
heroku run rake db:bootstrap_admin ADMIN_USERNAME=<username> --app <face-cloak-api-app-name>
```

Verify the deployed API:
```bash
curl https://<face-cloak-api-app-name>.herokuapp.com/
curl -X POST https://<face-cloak-api-app-name>.herokuapp.com/api/v1/accounts \
  -H 'Content-Type: application/json' \
  -d '{"username":"demo","email":"demo@example.com","password":"password123"}'
```

## Release Check
Before submitting pull requests, please check if specs, style, and dependency audits pass:
```bash
rake release_check
```

## For Contributors

- **Database schema** — see [`docs/schema.md`](docs/schema.md) for the
  entity-relationship diagram and the rationale behind encrypted columns,
  keyed-hash lookup, role enumeration, and cascade behavior.
- **Image storage** — development/test use environment-specific local files
  under `db/local/storage/<environment>`;
  production defaults to S3 and stores `images/<uuid>.<ext>` object keys in
  `images.file_data`.
