# FaceCloak API v1 Technical Reference

Detailed technical documentation for FaceCloak API routes.

## Global Standards

### Base URL
`http://localhost:3000/api/v1` (Development)

### Required Headers
- **Protected Routes**: `Authorization: Bearer <auth_token>`
- **JSON Requests**: `Content-Type: application/json`

### Common Response Codes
- `200 OK`: Request succeeded.
- `201 Created`: Resource created successfully.
- `202 Accepted`: Request accepted for processing (e.g., email registration).
- `400 Bad Request`: Validation failure, missing parameters, or malformed JSON.
- `401 Unauthorized`: Missing, invalid, or expired authentication token.
- `403 Forbidden`: Authenticated account lacks permissions for this operation.
- `404 Not Found`: Resource does not exist or is intentionally hidden.

---

## 1. Authentication

### POST `/auth/authenticate`
Authenticates a user and issues an auth token.
- **Request Body**:
  ```json
  {
    "username": "alice",
    "password": "password123"
  }
  ```
- **Success Response (200)**:
  ```json
  {
    "type": "authenticated_account",
    "attributes": {
      "account": { "type": "account", "attributes": { ... }, "include": { ... } },
      "auth_token": "string (JWT-like encrypted token)"
    }
  }
  ```

### POST `/auth/register`
Validates email and sends a registration verification link.
- **Request Body**:
  ```json
  {
    "email": "user@example.com",
    "verification_url": "https://app.example.com/verify/token"
  }
  ```
- **Success Response (202)**: `{ "message": "Verification email sent" }`

---

## 2. Accounts

### GET `/accounts`
Lists all accounts (Admins see all, Users see themselves).
- **Success Response (200)**:
  ```json
  {
    "data": [ { "id": "UUID", "username": "alice", "policies": { ... } } ],
    "capabilities": { "is_admin": false, ... }
  }
  ```

### POST `/accounts`
Creates a new account (Public route).
- **Request Body**: `{ "username": "...", "email": "...", "password": "..." }`

### GET `/accounts/:username`
Retrieves account metadata and permissions.
- **Success Response (200)**: Includes `policies` (what you can do to them) and `capabilities` (what you can do in general).

### POST `/accounts/search`
Finds an account by email (keyed-hash lookup).
- **Request Body**: `{ "email": "user@example.com" }`

---

## 3. Images

### GET `/images`
Lists all images you are authorized to see (owned or assigned).
- **Success Response (200)**: Array of image metadata with `policies`.

### POST `/images`
Uploads an image. Authenticated user becomes the Owner.
- **Request Headers**: `Content-Type: multipart/form-data`
- **Request Body**: `file` (binary data)
- **Success Response (201)**: Returns the newly created Image object.

### GET `/images/:id`
Returns the **binary image content**.
- **Privacy Logic**: Returns raw data ONLY if ALL face records are set to `unveil`. Otherwise returns a blurred/masked version.
- **Response Headers**: Sets `X-Privacy-Filtered: true` if the image was modified for privacy.

### GET `/images/:id/raw`
Returns the **raw original binary** regardless of face state.
- **Auth**: Owner or Admin only. Others receive `404`.

### DELETE `/images/:id`
Deletes image and all associated face records and files.
- **Auth**: Owner or Admin only.

---

## 4. Face Records

### GET `/images/:id/face_records`
Lists all detected faces in a specific image.
- **Auth**: Owner only.

### GET `/face_records/:id`
Get details of a specific face record.
- **Auth**: Owner or Assignee only.

### POST `/face_records/:id/assignment`
Assigns a face to a user for their decision.
- **Auth**: Owner only.
- **Request Body**: `{ "assigned_user_id": "UUID" }`

### POST `/face_records/:id/respond`
Sets the privacy preference (cloak type) for the face.
- **Auth**: Assignee only (Zero-Trust).
- **Request Body**: `{ "cloak_type": "pixelate" }`
- **Valid Options**: `blur`, `pixelate`, `comics`, `sunglasses`, `mask`, `unveil`

### POST `/face_records/:id/decline`
Declines the assignment.
- **Auth**: Assignee only.
- **Behavior**: Clears assignment and resets cloak to `blur`.

---

## 5. Audit Logs

### GET `/images/:id/logs`
Audit logs for all faces in an image (Owner only).

### GET `/face_records/:id/logs`
Audit logs for a specific face (Owner or Assignee).
