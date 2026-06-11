# frozen_string_literal: true

module FaceCloak
  # OAuth-style authorization scope carried inside an AuthToken.
  class AuthScope
    ALL = '*'
    READ = 'read'
    WRITE = 'write'
    FULL = '*:write'
    READ_ONLY = '*:read'

    SEPARATOR = ' '
    DIVIDER = ':'
    VALID_PERMISSIONS = [READ, WRITE].freeze

    class InvalidScopeError < StandardError; end

    def initialize(scopes = FULL)
      @scopes_str = scopes.to_s.strip
      raise InvalidScopeError, 'Auth scope is required' if @scopes_str.empty?

      @scopes = {}
      @scopes_str.split(SEPARATOR).each { |scope| add_scope(scope) }
    end

    def can_read?(resource)
      readable?(ALL) || readable?(resource)
    end

    def can_write?(resource)
      writeable?(ALL) || writeable?(resource)
    end

    def to_s
      @scopes_str
    end

    private

    def readable?(resource)
      writeable?(resource) || permission_granted?(resource, READ)
    end

    def writeable?(resource)
      permission_granted?(resource, WRITE)
    end

    def permission_granted?(resource, permission)
      @scopes[resource]&.include?(permission) || false
    end

    def add_scope(scope)
      resource, permission = scope.split(DIVIDER, 2)
      validate_scope!(resource, permission)

      @scopes[resource] ||= []
      @scopes[resource] << permission
    end

    def validate_scope!(resource, permission)
      raise InvalidScopeError, "Invalid auth scope: #{resource}:#{permission}" if
        resource.to_s.empty? || permission.to_s.empty? || !VALID_PERMISSIONS.include?(permission)
    end
  end
end
