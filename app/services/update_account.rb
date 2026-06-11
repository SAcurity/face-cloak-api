# frozen_string_literal: true

module FaceCloak
  # Updates account profile fields after policy and password checks.
  class UpdateAccount
    class ForbiddenError < StandardError; end
    class InvalidPasswordError < StandardError; end

    def self.call(viewer:, target:, update_data:, auth_scope:)
      policy = AccountPolicy.new(viewer, target, auth_scope:)
      raise ForbiddenError, 'Forbidden' unless policy.can_edit?

      changes = permitted_changes(target, update_data, viewer)
      raise ArgumentError, 'No account updates provided' if changes.empty?

      target.update(changes)
      target
    rescue Sequel::UniqueConstraintViolation
      raise ArgumentError, 'Username already exists'
    end

    def self.permitted_changes(target, update_data, viewer)
      changes = {}
      changes[:username] = update_data[:username].to_s.strip if update_data.key?(:username)
      changes[:password] = update_data[:new_password] if update_data.key?(:new_password)
      validate_username!(changes[:username]) if changes.key?(:username)
      validate_password_change!(target, update_data, viewer) if changes.key?(:password)
      changes
    end

    def self.validate_username!(username)
      raise ArgumentError, 'Username is required' if username.empty?
    end

    def self.validate_password_change!(target, update_data, viewer)
      raise ArgumentError, 'New password is required' if update_data[:new_password].to_s.empty?
      raise ForbiddenError, 'Only the account owner can change password' unless viewer.id == target.id
      return if target.password_digest.to_s.empty?
      return if target.password?(update_data[:current_password])

      raise InvalidPasswordError, 'Current password is incorrect'
    end
  end
end
