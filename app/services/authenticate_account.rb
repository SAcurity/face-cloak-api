# frozen_string_literal: true

module FaceCloak
  # Service object to authenticate an account
  class AuthenticateAccount
    class UnauthorizedError < StandardError; end

    def self.call(username:, password:)
      account = Account.first(username:)
      raise UnauthorizedError, 'Invalid credentials' unless account&.password?(password)

      account
    rescue StandardError
      raise UnauthorizedError, 'Invalid credentials'
    end
  end
end
