# 3-user-accounts — User Accounts & Authentication [COMPLETED]

## Goal
Implement secure user accounts with salted/hashed passwords, many-to-many associations for privacy management, and roles for access control. Transition the system to a hybrid ID architecture (Integers for Users, UUIDs for sensitive resources) and move all business logic to Service Objects.

## Strategy
1.  **Account Management (Integer IDs)**: Align with teacher's `tyto-api` patterns for User and Role management using incrementing integers. Use SCrypt for passwords and HMAC for searchable emails.
2.  **Privacy Autonomy (UUID IDs)**: Maintain UUIDs for `Image` and `FaceRecord` to ensure resource unpredictability and security.
3.  **Service-Oriented Architecture (SOA)**: Refactor all business logic from controllers into focused Service Objects to ensure reusability and clean code.
4.  **Automatic Privacy Assignment**: Atomically link FaceRecords to Assignees and grant those Assignees access to the parent Image within a single transaction.

## Executed Items

### 1. Hybrid Database Schema
- [x] **Integer-based Accounts**: Refactored `Accounts` and `Roles` to use `primary_key :id` (Integer).
- [x] **UUID-based Resources**: Restored `Images` and `FaceRecords` to use `uuid :id, primary_key: true`.
- [x] **Stand-alone Join Tables**: Followed teacher's pattern with independent migrations for `accounts_roles` and `accounts_images`.

### 2. Service Objects (Logic Refactoring)
- [x] `CreateAccount`: Secure registration.
- [x] `AuthenticateAccount`: Secure login.
- [x] `UploadImage`: Encapsulates image storage and record creation.
- [x] `CreateFaceRecord`: Handles manual face detection logging.
- [x] `AssignFaceRecord`: **Primary Privacy Logic**. Atomically assigns a face to a user and grants image access. Enforces "one face per user per image" constraint.
- [x] `RespondToFaceRecord`: Handles privacy response updates.

### 3. API & Controllers
- [x] **Thin Controller**: `app/controllers/app.rb` refactored to delegate all write operations to services.
- [x] **Search**: Search by email using HMAC hash.
- [x] **Automatic Access**: Verified that assigning a face record automatically updates the `accounts_images` access list.

### 4. Validation & Testing
- [x] **Hybrid Test Suite**: Updated all specs to handle Integer account IDs and UUID resource IDs.
- [x] **Pass Rate**: All 64 tests passing after major SOA refactor.
- [x] **RuboCop**: All style and design pattern issues resolved.

## Key Design Decisions
- **Hybrid ID System**: Balanced user-friendliness (Integers for accounts) with security (UUIDs for images).
- **Service Consolidation**: Merged generic image access with specific face assignment to prevent redundant API calls and simplify user workflow.
- **Transactional Integrity**: All multi-step operations (like assignment + logging) are wrapped in DB transactions.
