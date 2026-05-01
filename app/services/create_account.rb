# frozen_string_literal: true

module FaceCloak
  # Service object to create a new account
  class CreateAccount
    def self.call(account_data:)
      Account.create(account_data)
    rescue Sequel::ValidationFailed => e
      raise e.message
    rescue Sequel::UniqueConstraintViolation
      raise 'Username or email already exists'
    end
  end
end
