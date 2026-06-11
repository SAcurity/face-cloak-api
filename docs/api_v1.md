# FaceCloak API v1 Technical Reference

Detailed technical documentation for FaceCloak API routes.

## Global Standards

### Base URL
`http://localhost:3000/api/v1` (Development)

### Required Headers
- **Protected Routes**: `Authorization: Bearer <auth_token>`
- **JSON Requests**: `Content-Type: application/json`
- **Signed Public POST Requests**: Public POST routes that do not carry a Bearer token must send a signed body.

### Signed Public Requests
The following public POST routes require a client signature:

- `POST /auth/authenticate`
- `POST /auth/register`
- `POST /auth/sso`
- `POST /accounts`
- `POST /accounts/search`

Signed request format:

```json
{
  "data": {
    "username": "alice",
    "password": "password123"
  },
  "signature": "base64-ed25519-signature"
}
```

The signature is calculated over `data.to_json` with the client signing key. The API stores only `VERIFY_KEY` in production; `SIGNING_KEY` is for the Web App client and local tests/dev only. Authenticated mutation routes remain protected by Bearer token, auth scope, and resource policies. Multipart image upload is not wrapped in signed JSON.

### Auth Scopes
Auth tokens carry an encrypted authorization scope. Password login and SSO login issue full session tokens (`*:write`). Account detail responses include a reduced read-only API key (`*:read`) that can read protected resources but cannot upload, delete, assign, respond, decline, or otherwise mutate state.

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
Authenticates a user and issues a full-scope auth token.
- **Request Body**: Signed public request whose `data` is:
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

### POST `/auth/sso`
Authenticates a Google SSO user after the Web App completes the OAuth/OIDC browser flow.
- **Request Body**: Signed public request whose `data` is:
  ```json
  {
    "provider": "google",
    "id_token": "google OIDC id_token",
    "jwks": { "keys": [] }
  }
  ```
- **Success Response (200)**: Same envelope as password authentication.
- **Validation**: The API verifies the JWT signature, `aud`, `iss`, expiration, subject, email, and `email_verified`.
- **Note**: The API uses `jwt` and `http` only; it does not use Google's packaged SSO gems. The Web App owns the Google OAuth `state` nonce: it must create, store, and verify `state` before sending the signed SSO payload to the API.

### POST `/auth/register`
Validates email and sends a registration verification link.
- **Request Body**: Signed public request whose `data` is:
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
    "data": [
      {
        "id": 1,
        "username": "alice",
        "email": "alice@example.com",
        "created_at": "timestamp",
        "updated_at": "timestamp",
        "policies": { ... }
      }
    ],
    "capabilities": { "is_admin": false, ... }
  }
  ```
- **Auth**: Admins see all accounts; regular users see only themselves.

### POST `/accounts`
Creates a new account (Public route).
- **Request Body**: Signed public request whose `data` is `{ "username": "...", "email": "...", "password": "..." }`

### GET `/accounts/:username`
Retrieves account metadata and permissions, and returns a read-only API key for that account.
- **Success Response (200)**:
  ```json
  {
    "data": {
      "type": "authorized_account",
      "attributes": {
        "account": { "type": "account", "attributes": { ... }, "policies": { ... } },
        "auth_token": "read-only scoped token"
      }
    }
  }
  ```

### PUT `/accounts/:username`
Updates account settings.
- **Auth**: The account owner or an admin can change username. Only the account owner can change password.
- **Request Body**:
  ```json
  {
    "username": "new_username",
    "current_password": "old-password",
    "new_password": "new-password"
  }
  ```
- **Password Rule**: Local password accounts must provide `current_password`; SSO-only accounts may set their first local password while authenticated.

### DELETE `/accounts/:username`
Deletes an account.
- **Auth**: Admin only; admins cannot delete themselves.
- **Behavior**: Deletes the account and removes owned image files from storage.

### POST `/accounts/search`
Finds an account by username or email.
- **Request Body**: Signed public request whose `data` is:
  ```json
  { "username": "alice" }
  ```
  OR
  ```json
  { "email": "user@example.com" }
  ```
- **Note**: Username lookup is direct, while email lookup is performed via keyed-hash (blind index).

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
- **Response Data**: Each log includes the action snapshot captured when the log was written: `assigned_user_id`, `assigned_user`, and `cloak_type`.

### GET `/face_records/:id/logs`
Audit logs for a specific face (Owner or Assignee).
- **Response Data**: Each log includes the action snapshot captured when the log was written: `assigned_user_id`, `assigned_user`, and `cloak_type`.

---

## 6. Browser Security

### Security Headers
All API responses send conservative browser security headers, including `X-Content-Type-Options`, `X-Frame-Options`, `Referrer-Policy`, `Permissions-Policy`, and a restrictive Content Security Policy.

### POST `/security/csp-report`
Receives browser CSP violation reports.

- **Auth**: None.
- **Signed Request**: Not required. Browser-generated CSP reports cannot attach the client request signature.
- **Success Response**: `204 No Content`.

### Asset Integrity
`face-cloak-api` does not serve third-party browser scripts, stylesheets, or fonts. The Web App must attach SRI hashes to third-party browser assets.
