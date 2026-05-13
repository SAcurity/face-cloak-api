# Database Schema

The database schema for FaceCloak API is designed to support automated face detection and a zero-trust privacy control model.

```mermaid
erDiagram
    accounts {
        integer id PK
        string username UK "not null"
        string email_secure "not null"
        string email_hash "not null, indexed"
        string password_digest "not null"
        datetime created_at
        datetime updated_at
    }

    roles {
        integer id PK
        string name UK "not null"
        datetime created_at
        datetime updated_at
    }

    accounts_roles {
        integer account_id FK
        integer role_id FK
    }

    images {
        uuid id PK
        integer owner_id FK "not null"
        string file_name "not null"
        string file_data "not null"
        datetime created_at
        datetime updated_at
    }

    face_records {
        uuid id PK
        uuid image_id FK "not null"
        integer assigned_user_id FK "nullable"
        datetime assigned_at
        datetime responded_at
        string cloak_type "default: blur"
        float x_min
        float y_min
        float x_max
        float y_max
        string landmarks "JSON string, optional"
        datetime created_at
        datetime updated_at
    }

    action_logs {
        integer id PK
        uuid face_record_id FK "not null"
        integer actor_id FK "not null"
        string action "not null"
        datetime created_at
    }

    accounts_images {
        uuid image_id FK
        integer account_id FK
    }

    accounts ||--o{ images : owns
    images ||--o{ face_records : contains
    accounts o|--o{ face_records : assigned_user
    face_records ||--o{ action_logs : records
    accounts ||--o{ action_logs : acts
    accounts ||--o{ accounts_roles : has
    roles ||--o{ accounts_roles : grants
    images ||--o{ accounts_images : grants_access
    accounts ||--o{ accounts_images : can_access
```

## Entities

- **Accounts**: Stores user information with encrypted PII (email) and salted/hashed passwords.
- **Roles**: Enumerates system roles (e.g., owner, user).
- **Images**: Stores image metadata and links to physical storage. Images are owned by an account.
- **FaceRecords**: Represents detected faces within an image. Each face can be assigned to a user who controls its privacy state. Coordinates are stored as normalized floats, and `landmarks` is an optional JSON string used only when a detector provides landmark data.
- **ActionLogs**: Audit trail for all state-changing operations on face records.
- **Join Tables**:
    - `accounts_roles`: Many-to-many relationship between users and roles.
    - `accounts_images`: Manages access permissions for assignees.

## Constraints & Relationships

- `accounts.username` is unique.
- `roles.name` is unique.
- `images` has a unique `[owner_id, file_name]` constraint.
- `face_records` has a unique `[image_id, assigned_user_id]` constraint, enforcing one assigned face per user per image when `assigned_user_id` is present.
- Deleting an `image` cascades to its `face_records`.
- Deleting a `face_record` cascades to its `action_logs`.
- Deleting an assigned `account` sets `face_records.assigned_user_id` to `NULL`.
- Deleting an owner account cascades to owned `images`.
- Deleting an actor account cascades to its `action_logs`.

## Security Rationale

- **Hybrid IDs**: Incrementing integers for internal account management; UUIDs for public-facing resources (Images, FaceRecords) to prevent enumeration attacks.
- **PII Protection**: Sensitive fields like email are stored as encrypted ciphertext with a separate HMAC hash for deterministic lookup.
- **Cascade Behavior**: Strict foreign key constraints ensure that deleting an image automatically removes its associated face records and audit logs.
