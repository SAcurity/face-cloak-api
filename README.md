# FaceCloak API

API for configuring privacy controls for detected faces in images.

## Routes

All routes return JSON except `GET /api/v1/images/[ID]`, which returns binary image content.
Uploaded images are stored in local storage, while the database keeps a storage key in `file_data`.
Seed image records may still provide Base64 input data, which the app converts into local storage files when records are created.
`images` and `face_records` use opaque generated string IDs rather than sequential numeric IDs. Generated IDs are prefixed by resource type, such as `img_...` and `fac_...`.

### Root

- GET `/`
  Returns API metadata and available resources.

### Images

- GET `/api/v1/images`
  Returns all image records as JSON.

- POST `/api/v1/images`
  Creates an image record.
  Multipart form fields:
  - `owner_id`
  - `file` (uploaded image file)
  The API reads `file_name` directly from the uploaded file metadata, stores the binary in local storage, and saves the generated storage key in `file_data`.
  If the same owner uploads the same file name more than once, the API automatically suffixes the later names such as `photo-1.png`.
  Different owners may keep the same original file name without suffixing.

- GET `/api/v1/images/:id`
  Returns the image binary for that record, with `Content-Type` derived from `file_name`.
  Opening this route in a browser will usually display the image directly.

- DELETE `/api/v1/images/:id`
  Deletes an image record, its stored image file, and any dependent face records/action logs.
  Once deleted, repeating the same request returns `404` because the image no longer exists.
  - Required header:
    - `X-Actor-Id` must match the image owner.

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
  Clears the assigned user from a face record and resets its effective cloak state back to the default `blur`.
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
  Returns all action logs for face records that belong to the specified image.

- GET `/api/v1/face_records/:id/logs`
  Returns all action logs for the specified face record.

## Install

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
