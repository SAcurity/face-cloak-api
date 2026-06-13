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
      role_names = permitted_role_names(target, update_data, viewer)
      raise ArgumentError, 'No account updates provided' if changes.empty? && role_names.nil?

      target.update(changes) unless changes.empty?
      update_roles(target, role_names) if role_names
      target.refresh
    rescue Sequel::UniqueConstraintViolation
      raise ArgumentError, 'Username already exists'
    end

    def self.permitted_changes(target, update_data, viewer)
      changes = {}
      changes[:username] = update_value(update_data, :username).to_s.strip if update_key?(update_data, :username)
      changes[:password] = update_value(update_data, :new_password) if update_key?(update_data, :new_password)
      validate_username!(changes[:username]) if changes.key?(:username)
      validate_password_change!(target, update_data, viewer) if changes.key?(:password)
      changes
    end

    def self.permitted_role_names(target, update_data, viewer)
      return nil unless update_key?(update_data, :identity) || update_key?(update_data, :system_roles)

      ensure_role_update_allowed!(target, viewer)
      identity = identity_from_update_data(update_data)
      validate_identity!(identity)
      identity == 'admin' ? %w[member admin] : %w[member]
    end

    def self.ensure_role_update_allowed!(target, viewer)
      raise ForbiddenError, 'Only admins can change identity' unless viewer.admin?
      raise ForbiddenError, 'Admins cannot change their own identity' if viewer.id == target.id
    end

    def self.identity_from_update_data(update_data)
      identity = update_value(update_data, :identity).to_s.strip.downcase
      identity.empty? ? roles_identity(update_value(update_data, :system_roles)) : identity
    end

    def self.validate_username!(username)
      raise ArgumentError, 'Username is required' if username.empty?
    end

    def self.validate_password_change!(target, update_data, viewer)
      raise ArgumentError, 'New password is required' if update_value(update_data, :new_password).to_s.empty?
      raise ForbiddenError, 'Only the account owner can change password' unless viewer.id == target.id
      return if target.password_digest.to_s.empty?
      return if target.password?(update_value(update_data, :current_password))

      raise InvalidPasswordError, 'Current password is incorrect'
    end

    def self.validate_identity!(identity)
      return if %w[admin member].include?(identity)

      raise ArgumentError, 'Identity must be admin or member'
    end

    def self.roles_identity(role_names)
      Array(role_names).map(&:to_s).include?('admin') ? 'admin' : 'member'
    end

    def self.update_roles(target, role_names)
      target.remove_all_system_roles
      role_names.each do |role_name|
        role = Role.first(name: role_name) || Role.create(name: role_name)
        target.add_system_role(role)
      end
      target.db[:accounts].where(id: target.id).update(updated_at: Time.now)
    end

    def self.update_key?(update_data, key)
      update_data.key?(key) || update_data.key?(key.to_s)
    end

    def self.update_value(update_data, key)
      update_data[key] || update_data[key.to_s]
    end
  end
end
