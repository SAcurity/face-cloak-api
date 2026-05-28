# PLAN.7-policies: Policies and Validation (Tyto Style)

This plan outlines the implementation of centralized resource policies, policy scopes, and policy summaries in the `face-cloak-api` project, following the minimalist `tyto-api` architecture.

## Goals
1. **Authorization Status Codes**: Ensure proper use of 401 (Authentication) and 403 (Authorization).
2. **Formal Policies**: Create policy objects in `app/policies/` for `Account`, `Image`, and `FaceRecord`.
3. **Policy Scopes**: Implement policy scopes to filter resource lists at the database level.
4. **Policy Summaries**: Include policy summaries (`policies` and `capabilities` keys) in API JSON responses.
5. **Role Predicates**: Add helper methods to `Account` and `Role` models (e.g., `account.admin?`).

---

## Phase 1: Preparation & Infrastructure
- [x] Remove `dry-validation` from `Gemfile`.
- [x] Delete `app/forms/` directory.
- [x] Update `require_app.rb` to remove `forms` and add `policies`.
- [x] Add `admin?` helper method to `Account` model.

## Phase 2: Resource Policies
Create policy objects following the `Tyto` pattern.

- [x] **AccountPolicy**:
    - `can_view?`: Self or Admin.
    - `can_edit?`: Self or Admin.
    - `can_delete?`: Admin only.
    - `summary`, `index_summary`, `capabilities`.
- [x] **ImagePolicy**:
    - `can_view?`: Owner, Assignee, or Admin.
    - `can_view_raw?`: Owner or Admin.
    - `can_delete?`: Owner or Admin.
- [x] **FaceRecordPolicy**:
    - `can_view?`: Owner, Assignee, or Admin.
    - `can_assign?`: Owner or Admin.
    - `can_respond?`: Assignee only (Zero-Trust).

## Phase 3: Policy Scopes
- [x] **AccountPolicy::AccountScope**: Admins see all; users see themselves.
- [x] **ImagePolicy::AccountScope**: Users see images they own or are assigned to.

## Phase 4: Controller & Service Refactoring
- [x] **Refactor Routes**: Remove `Forms::*` calls. Direct model operations with `begin...rescue`.
- [x] **Authorization**: Use policy objects in routes and services. Return 403 for Forbidden.
- [x] **JSON Envelopes**: Add `policies` to resource reads and `capabilities` to self-account read.

## Phase 5: Verification
- [x] Run `rake spec` to ensure no regressions.
- [x] Verify 403 Forbidden paths in integration tests.
