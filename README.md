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

All routes return JSON except `GET /api/v1/images/[ID]`, which returns filtered/raw binary image content.

### Root
- ```bash
  GET /
  ```
  API metadata and resources.

### Images
- ```bash
  GET /api/v1/images
  ```
  List all image metadata.
- ```bash
  POST /api/v1/images
  ```
  Upload image (automatically triggers face detection).
### Images
- ```bash
  GET /api/v1/images/:id
  ```
  Get image file (Privacy-First Default).
  - **Everyone (including Owner)**: Returns raw binary ONLY if ALL faces are `unveil`.
  - **Privacy Filter**: Otherwise returns `PRIVACY_FILTERED_DATA` with `X-Privacy-Filtered: true` header.
- ```bash
  GET /api/v1/images/:id/raw
  ```
  Get raw image file (Administrative Access).
  - **Owner ONLY**: Returns **raw binary** regardless of face states.
  - **Others**: Returns `403 Forbidden`.
- ```bash
  DELETE /api/v1/images/:id
  ```

  Delete image and all associated records.

### Face Records
- ```bash
  GET /api/v1/face_records
  ```
  List all face records.
- ```bash
  POST /api/v1/face_records/:id/assignment
  ```
  Assign a face to a user (Owner only).
- ```bash
  DELETE /api/v1/face_records/:id/assignment
  ```
  Clear assignment (Owner only).
- ```bash
  POST /api/v1/face_records/:id/respond
  ```
  Set mask/unveil preference (Assignee only).

### Action Logs
- ```bash
  GET /api/v1/images/:id/logs
  ```
  Audit logs for an image.
- ```bash
  GET /api/v1/face_records/:id/logs
  ```
  Audit logs for a specific face.

## Install
1. ```bash
   bundle install
   ```
2. ```bash
   cp config/secrets-example.yml config/secrets.yml
   ```
3. ```bash
   rake db:migrate
   ```

## Test
- ```bash
  RACK_ENV=test rake db:migrate
  ```
- ```bash
  rake spec
  ```

## Verification (Release Check)
```bash
rake release_check
```
