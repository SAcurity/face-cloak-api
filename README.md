# FaceCloak API

API for configuring privacy controls for detected faces in images.

## Architecture & Security Standards (Hardening)

This project follows strict security hardening standards:
- **Zero-Trust Privacy**: Image owners cannot access unmasked data unless specifically authorized by the subject.
- **Data Protection (PII)**: Personally Identifiable Information (`owner_id`, `assigned_user_id`, `actor_id`) is encrypted at rest using `RbNaCl`.
- **Opaque Identifiers**: All resources use standard **UUID v4** strings to prevent resource enumeration.
- **Audit Logging**: All state-changing operations are automatically logged with actor attribution.
- **PostgreSQL Ready**: Optimized for PostgreSQL native `UUID` types while maintaining SQLite compatibility.

## Core Business Rules

### 1. Automated Detection
- When an image is uploaded via `POST /api/v1/images`, the system automatically "detects" faces and creates corresponding `FaceRecord` entries.
- All new faces default to a `blur` state.

### 2. Zero-Trust Access Control
- **Owner Role**: Can upload images and *assign* faces to users.
- **Assignee Role**: ONLY the assigned user can decide to `unveil` their face.
- **Privacy Barrier**: The image owner **cannot** unveil a face they are not assigned to.
- **Rendered Output**: `GET /api/v1/images/:id` only returns raw data if **ALL** faces are unveiled. If any face is unassigned or masked, it returns a privacy-filtered placeholder.

## Routes

All routes return JSON except `GET /api/v1/images/:id` and `GET /api/v1/images/:id/raw`, which return binary image content.

### Root

- GET `/`
  Returns API metadata and resources.

### Images

- GET `/api/v1/images`
  Returns all image metadata as JSON.

- POST `/api/v1/images`
  Uploads an image and automatically triggers face detection.
  - Request body:
    - `owner_id`
    - `file`

- GET `/api/v1/images/:id`
  Returns the default privacy-filtered image view.
  - Raw binary is returned only when all face records are effectively `unveil`.
  - Otherwise the API returns `PRIVACY_FILTERED_DATA_FOR_<image_id>` and sets `X-Privacy-Filtered: true`.

- GET `/api/v1/images/:id/raw`
  Returns the raw image binary regardless of face state.
  - Required header:
    - `X-Actor-Id` must match the image owner.

- DELETE `/api/v1/images/:id`
  Deletes an image and all associated face records and action logs.
  - Required header:
    - `X-Actor-Id` must match the image owner.

- GET `/api/v1/images/:id/logs`
  Returns all action logs for the specified image.

### Face Records

- GET `/api/v1/face_records`
  Returns all face records as JSON.

- POST `/api/v1/face_records`
  Creates a face record for an existing image.
  - Request body:
    - `image_id`
    - `cloak_type` (optional; defaults to the model behavior)
  - Required header:
    - `X-Actor-Id` must match the image owner.

- GET `/api/v1/face_records/:id`
  Returns a single face record as JSON.

- POST `/api/v1/face_records/:id/assignment`
  Assigns a face record to a user.
  - Request body:
    - `assigned_user_id`
  - Required header:
    - `X-Actor-Id` must match the image owner.

- DELETE `/api/v1/face_records/:id/assignment`
  Clears the assigned user from a face record and resets its effective cloak state to `blur`.
  - Required header:
    - `X-Actor-Id` must match the image owner.

- POST `/api/v1/face_records/:id/respond`
  Updates the selected cloak type for the assigned user.
  - Request body:
    - `cloak_type`
  - Required header:
    - `X-Actor-Id` must match `assigned_user_id`.

### Action Logs

- GET `/api/v1/images/:id/logs`
  Returns all action logs for the specified image.

- GET `/api/v1/face_records/:id/logs`
  Returns all action logs for the specified face record.

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

Copy config/secrets-example.yml to config/secrets.yml and adjust as needed.

Setup development database once:

```bash
rake db:migrate
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

## Run

Run this API using:

```bash
puma
```

Or you can rerun the API using:

```bash
rake rerun
```

## Release Check
Before submitting pull requests, please check if specs, style, and dependency audits pass:

```bash
rake release_check
```
