# frozen_string_literal: true

require 'json'
require_relative 'securable'

module FaceCloak
  # Secure, time-limited token for account registration.
  class RegistrationToken
    extend Securable

    class ExpiredTokenError < StandardError; end
    class InvalidTokenError < StandardError; end

    # 30 minutes in seconds
    THIRTY_MINUTES = 30 * 60

    def self.setup(base_key)
      setup_secret_key(base_key)
    end

    def self.tokenize(message)
      base_encrypt(JSON.generate(message))
    end

    def self.detokenize(ciphertext64)
      JSON.parse(base_decrypt(ciphertext64))
    rescue StandardError
      raise InvalidTokenError
    end

    # Creates a token containing an email and an expiration timestamp.
    def initialize(email, expiration = THIRTY_MINUTES)
      @payload = { 'email' => email }
      @expiration = (Time.now + expiration).to_i
      @token = self.class.tokenize('payload' => @payload, 'exp' => @expiration)
    end

    def self.load(token)
      contents = detokenize(token)
      raise ExpiredTokenError if Time.now.to_i > contents['exp']

      contents['payload']
    rescue ExpiredTokenError
      raise ExpiredTokenError
    rescue StandardError
      raise InvalidTokenError
    end

    def to_s
      @token
    end
  end
end
