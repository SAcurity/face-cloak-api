# FaceCloak API

API for configuring privacy controls for detected faces in images.

## Core Business Rules

### 1. Automated Detection
- When an image is uploaded via `POST` `/api/v1/images`, the system automatically "detects" faces and creates two corresponding `FaceRecord` entries.
- All new faces default to a `blur` state.
- Duplicate file names for the same owner are automatically suffixed, such as `repeat-1.png`.

### 2. Zero-Trust Access Control
- **Owner Role**: Can upload images, create face records, assign face records, unassign face records, and view image-level logs.
- **Assignee Role**: ONLY the assigned user can decide the face's `cloak_type`.
- **Privacy Barrier**: The image owner cannot respond to a face they are not assigned to.
- **Assignment Constraint**: A user can only be assigned to ONE face record per image.
- **Rendered Output**: `GET` `/api/v1/images/:id` only returns raw data if the image has face records and **ALL** faces are effectively `unveil`. Otherwise it returns a privacy-filtered placeholder.

### 3. Supported Values
- **Cloak Types**: `blur`, `pixelate`, `comic`, `sunglasses`, `mask`, `unveil`
- **Action Types**: `create`, `assign`, `unassign`, `respond`

## Database Schema

<img src="./db-schema.png" alt="Database schema" width="700">

## Routes

All routes return JSON except `GET` `/api/v1/images/:id` and `GET` `/api/v1/images/:id/raw`, which return binary image content.

### Root

- `GET` `/`
  Returns API metadata and resources.

### Accounts

- `POST` `/api/v1/accounts`
  Creates a new account.
  - Request body:
    - `username`
    - `email`
    - `password`
  - Returns `201` on success.
  - Returns `400` for invalid payload or duplicate username.

- `POST` `/api/v1/accounts/authenticate`
  Authenticates an account.
  - Request body:
    - `username`
    - `password`
  - Returns account data on success.
  - Returns `401` for invalid credentials.

- `POST` `/api/v1/accounts/search`
  Finds an account by email.
  - Request body:
    - `email`
  - Email lookup is performed via the stored keyed hash.
  - Returns `404` if no account matches.

- `GET` `/api/v1/accounts/:username`
  Returns account metadata for the given username.
  - Returns `404` if the account does not exist.

### Images

- `GET` `/api/v1/images`
  Returns all image metadata as JSON.

- `POST` `/api/v1/images`
  Uploads an image and automatically triggers face detection.
  - Request body (Multipart):
    - `owner_id`
    - `file` (Uploaded image)
  - `owner_id` must belong to an existing account.
  - The uploaded file is stored in local storage.
  - The API auto-creates two `FaceRecord` entries with default `blur`.

- `GET` `/api/v1/images/:id`
  Returns the default privacy-filtered image view.
  - **Everyone (including Owner)**: Raw binary is returned ONLY when the image has face records and ALL face records are effectively `unveil`.
  - Otherwise the API returns `PRIVACY_FILTERED_DATA_FOR_<image_id>` and sets `X-Privacy-Filtered: true`.

- `GET` `/api/v1/images/:id/raw`
  Returns the raw image binary regardless of face state.
  - **Owner ONLY**: Required header `X-Actor-Id` must match the image owner.

- `GET` `/api/v1/images/:id/logs`
  Returns all action logs for all faces belonging to the specified image.
  - **Owner ONLY**: Required header `X-Actor-Id` must match the image owner.

- `DELETE` `/api/v1/images/:id`
  Deletes an image and all associated face records and action logs.
  - **Owner ONLY**: Required header `X-Actor-Id` must match the image owner.
  - Also removes the stored file from local storage.

### Face Records

- `GET` `/api/v1/face_records`
  Returns all face records as JSON.

- `POST` `/api/v1/face_records`
  Creates a face record for an existing image manually.
  - Request body:
    - `image_id`
    - `cloak_type` (optional)
  - **Owner ONLY**: Required header `X-Actor-Id` must match the image owner.
  - Automatically creates a `create` action log.

- `GET` `/api/v1/face_records/:id`
  Returns a single face record as JSON.

- `POST` `/api/v1/face_records/:id/assignment`
  Assigns a face record to a user.
  - Request body:
    - `assigned_user_id`
  - **Owner ONLY**: Required header `X-Actor-Id` must match the image owner.
  - **Constraint**: The same user can only be assigned to ONE face record within the same image.
  - Also grants image access via the `accounts_images` join table.

- `DELETE` `/api/v1/face_records/:id/assignment`
  Clears the assigned user from a face record and resets its effective cloak state to `blur`.
  - **Owner ONLY**: Required header `X-Actor-Id` must match the image owner.
  - Clears `assigned_user_id`, `assigned_at`, and `responded_at`.
  - Automatically creates an `unassign` action log.

- `POST` `/api/v1/face_records/:id/respond`
  Updates the selected cloak type for the assigned user.
  - Request body:
    - `cloak_type`
  - **Assignee ONLY**: Required header `X-Actor-Id` must match `assigned_user_id`.
  - Automatically creates a `respond` action log.

### Action Logs

- `GET` `/api/v1/images/:id/logs`
  Returns all action logs for all faces belonging to the specified image.
  - **Owner ONLY**: Required header `X-Actor-Id` must match the image owner.

- `GET` `/api/v1/face_records/:id/logs`
  Returns all action logs for the specified face record.
  - **Owner or Assignee ONLY**: Required header `X-Actor-Id` must match either the image owner or the record assignee.

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

Copy config/secrets-example.yml to config/secrets.yml and adjust as needed:
```bash
cp config/secrets-example.yml config/secrets.yml
```

Required secrets:
- `DATABASE_URL`
- `DB_KEY`
- `HASH_KEY`

You can generate sample keys with:
```bash
rake newkey:db
rake newkey:hash
```

Setup development database once:
```bash
rake db:migrate
```

Optional seed data:
```bash
rake db:seed
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
bundle exec puma
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
